# DatadogCrashReporting — Architecture & Performance Analysis

Key findings on performance, memory, and architectural improvements for the
`DatadogCrashReporting` module. These are observations from the current codebase
after the Swift 6 concurrency migration.

---

## 1. Context encoding on every change is the main hot path

### Problem

Every time the SDK context changes, the following chain fires:

```
message bus → CrashContextCoreProvider.receive()
            → queue.async { self._context = crashContext }
            → didSet { _context.map(_callback) }
            → Task { await coordinator.inject(currentCrashContext:) }
            → JSONEncoder.encode(crashContext)       ← full serialization
            → kscrash_setUserInfoJSON(jsonString)     ← C string copy
```

`DatadogContext` changes are **high frequency** — network reachability transitions,
foreground/background, server time sync, etc. Each change triggers a full
`CrashContext` JSON encode (~20 fields including nested `Device`, `OperatingSystem`,
`UserInfo`, `NetworkConnectionInfo`, `CarrierInfo`, plus optional `RUMViewEvent`,
`RUMSessionState`, and attribute dictionaries).

`RUMViewEvent` alone is a massive struct (~50+ fields with nested objects). When it
changes frequently (e.g. resource/action/error counts incrementing), every update
triggers a full re-encode of the entire context.

### Impact

- **CPU**: `JSONEncoder.encode` + UTF-8 string conversion + `kscrash_setUserInfoJSON`
  (which internally copies the string) on every context change.
- **Memory**: Transient `Data` allocation for the JSON output, then a `String`
  allocation, then a C-string copy inside KSCrash. Three representations of the
  same data exist briefly.
- **Throughput**: Actor serialization means these encodes queue up — if context
  changes faster than encoding, the actor mailbox grows.

### Recommendations

#### A. Coalesce rapid context updates

The actor's `inject` could coalesce rapid updates by only encoding the
**latest** context when the actor processes the next message. One way:

```swift
actor CrashReportCoordinator {
    private var pendingContext: CrashContext?

    func inject(currentCrashContext: CrashContext) {
        pendingContext = currentCrashContext
        // Schedule encoding on next actor turn if not already pending
    }

    private func flushPendingContext() {
        guard let context = pendingContext else { return }
        pendingContext = nil
        if let data = encode(crashContext: context) {
            plugin.inject(context: data)
        }
    }
}
```

Or simpler: use a `Task` with a short debounce (e.g. 100ms). Most context changes
come in bursts (app launch, view transitions). Only the last state matters for crash
context — intermediate states are irrelevant if the app doesn't crash during that
window.

#### B. Diff-based encoding

Most context updates only change 1-2 fields (e.g. `networkConnectionInfo` changes
but `service`, `env`, `version` never change after init). Instead of re-encoding the
full struct:

1. Keep a cached `Data` of the last encoded context.
2. On change, compare which fields actually changed (the `Equatable` conformance
   already exists but only checks a subset of fields).
3. Only re-encode if meaningful fields changed.

**Note:** The current `CrashContext.==` already skips `lastRUMViewEvent`,
`lastRUMSessionState`, `lastRUMAttributes`, and `lastLogAttributes` in its equality
check. But the `didSet` on `_context` fires even when those omitted fields change
(e.g. a `viewEvent` update sets `_context?.lastRUMViewEvent` and triggers
`_callback`). This means the equality gate in `update(context:)` does NOT prevent
re-encoding when only RUM/log attributes change.

#### C. Skip encoding for fields that don't affect crash context

`CrashContext` includes `lastRUMAttributes` and `lastLogAttributes` which are
`[String: Encodable]` dictionaries. These get serialized on every change even though
they are only useful when a crash actually occurs. Consider:

- Lazy-encoding these dictionaries (store raw, encode only on crash read).
- Or deferring their serialization to the `readPendingCrashReport` path.

---

## 2. CrashContext struct is large and copied on every message

### Problem

`CrashContext` is a value type (struct) with ~20 fields. Every time the `_callback`
fires, the entire struct is copied:

```swift
private var _context: CrashContext? {
    didSet { _context.map(_callback) }
}
```

The callback then passes the struct into a `Task` closure, which copies it again
into the actor's isolation domain.

### Impact

- Two full copies per context change: one for the callback argument, one for the
  Task capture.
- `RUMViewEvent` is a deeply nested struct — copying it is non-trivial.

### Recommendations

#### A. Consider making CrashContext a class (reference type)

If `CrashContext` were a class (or wrapped in a reference-counted container),
the callback and Task would share a reference instead of copying. The trade-off
is losing value semantics, but the context is already behind a DispatchQueue for
synchronization.

#### B. Flatten the equality check

The current `==` ignores several fields (`lastRUMViewEvent`, `lastRUMSessionState`,
`lastRUMAttributes`, `lastLogAttributes`). But the `_context` still gets assigned
(and the callback still fires) when these fields change through the `didSet` chain
on `viewEvent`, `sessionState`, etc.

Consider restructuring `CrashContextCoreProvider` to only fire the callback when
`_context` has actually changed according to the `==` implementation. Currently, a
`viewEvent` update bypasses the `update(context:)` equality check:

```swift
private var viewEvent: RUMViewEvent? {
    didSet { _context?.lastRUMViewEvent = viewEvent }  // triggers didSet → callback
}
```

This means **every RUM view event update** fires a full encode even though the
equality check in `update(context:)` wouldn't consider it a change.

---

## 3. backtraceReporter creates a new instance on every access

### Problem

```swift
var backtraceReporter: BacktraceReporting? { KSCrashBacktrace(telemetry: telemetry) }
```

This computed property creates a new `KSCrashBacktrace` struct on every access.
While the struct is lightweight (only holds a `Telemetry` reference), it's called
from `CrashReporting.enableOrThrow` and potentially from the core when generating
backtraces.

### Recommendation

Store it as a `let` property initialized in `init`:

```swift
let backtraceReporter: BacktraceReporting?

init(...) {
    self.backtraceReporter = KSCrashBacktrace(telemetry: telemetry)
    ...
}
```

---

## 4. Static encoder/decoder on CrashReportingFeature

### Current design

```swift
internal static let crashContextEncoder: JSONEncoder = .dd.default()
internal static let crashContextDecoder: JSONDecoder = { ... }()
```

These are static properties on `CrashReportingFeature`, but they're used by the
`CrashReportCoordinator` actor.

### Observations

- **Thread safety**: `JSONEncoder` and `JSONDecoder` are not documented as thread-safe.
  In practice, Foundation's implementations are, but it's undocumented. The actor
  accesses them from its isolated context, which is fine for single-instance usage
  but could be a concern if multiple actors shared them.
- **Memory**: They live for the entire process lifetime since they're `static let`.
  This is fine — they're small and reused.
- **Ownership**: These belong logically to the coordinator (only consumer). Moving
  them there would improve encapsulation and make actor isolation explicit.

### Recommendation

Move to the actor as instance properties:

```swift
actor CrashReportCoordinator {
    private let encoder: JSONEncoder = .dd.default()
    private let decoder: JSONDecoder = { ... }()
}
```

This guarantees single-threaded access via actor isolation and removes the implicit
assumption about Foundation thread safety.

---

## 5. Filter pipeline allocates intermediate arrays on crash read

### Current design

The KSCrash filter pipeline processes crash reports through 4 filters sequentially:

```
DatadogTypeSafeFilter → DatadogMinifyFilter → DatadogDiagnosticFilter → DatadogCrashReportFilter
```

Each filter calls `filterReports(_:onCompletion:)`, which creates a new `[CrashReport]`
array via `.map`. For a single crash report, this means 4 array allocations.

### Impact

Minimal in practice — crash reading happens once per app launch and only when a
crash report exists. This is a cold path.

### Recommendation

No change needed. Readability and separation of concerns outweigh the negligible
allocation cost on this cold path.

---

## 6. Dual roles of CrashContextCoreProvider

### Problem

`CrashContextCoreProvider` serves as both:
1. A `FeatureMessageReceiver` (receives messages from the bus)
2. A `CrashContextProvider` (manages crash context state + fires change callbacks)

This dual role means the same object handles high-frequency message reception and
context serialization. The `DispatchQueue` serializes both concerns.

### Impact

- A burst of messages (e.g. multiple RUM payloads in quick succession) each schedule
  `queue.async` work items. Each `viewEvent` assignment triggers `_context` `didSet`,
  which fires the callback, which creates a `Task` for the actor.
- For N rapid messages, we get N `queue.async` blocks, N callback invocations, and
  N `Task` creations — even if only the last state matters.

### Recommendation

#### A. Batch updates within a single queue turn

Instead of individual `queue.async` per message type, accumulate changes and apply
them in one pass. The `receive(message:)` method could mark which fields are dirty
and schedule a single coalesced update:

```swift
func receive(message: FeatureMessage) {
    queue.async {
        switch message {
        case .context(let ctx): self.pendingContext = ctx
        case let .payload(view as RUMViewEvent): self.pendingViewEvent = view
        // ...
        }
        self.scheduleMerge()
    }
}

private func scheduleMerge() {
    // Only rebuild _context once per queue drain
}
```

#### B. Split the message receiver from the context provider

The `FeatureMessageReceiver` role could be a lightweight forwarder that batches
updates before handing them to the context provider. This separates the
high-frequency ingestion from the serialization concern.

---

## 7. Task allocation per context change

### Problem

Every context change creates an unstructured `Task`:

```swift
self.crashContextProvider.onCrashContextChange = { [weak coordinator] context in
    Task { await coordinator?.inject(currentCrashContext: context) }
}
```

Each `Task` allocates a task record, captures the context (value copy), and
enqueues on the cooperative thread pool. For high-frequency context changes,
this is a lot of small allocations.

### Recommendation

Instead of creating a `Task` per change, use a single long-lived `AsyncStream`
that feeds the actor:

```swift
actor CrashReportCoordinator {
    private let contextStream: AsyncStream<CrashContext>
    private let contextContinuation: AsyncStream<CrashContext>.Continuation

    func startListening() {
        Task {
            for await context in contextStream {
                if let data = encode(crashContext: context) {
                    plugin.inject(context: data)
                }
            }
        }
    }
}
```

The stream naturally coalesces if the actor can't keep up (with a
`.bufferingNewest(1)` policy), and avoids per-change Task allocations.

This aligns with the broader AsyncStream message bus migration planned in
`DatadogInternal/Resources/TODO.md`.

---

## 8. Memory retention summary

| Object | Lifetime | Held by | Notes |
|--------|----------|---------|-------|
| `CrashReportingFeature` | Process | Core (registered feature) | Holds coordinator + context provider |
| `CrashReportCoordinator` (actor) | Process | Feature | Holds plugin + sender + telemetry |
| `KSCrashPlugin` | Process | Coordinator | Holds `CrashReportStore` reference |
| `CrashContextCoreProvider` | Process | Feature (2x: as provider + messageReceiver) | Holds latest context + all RUM/log state |
| `MessageBusSender` | Process | Coordinator | `weak var core` — no retain cycle |
| `KSCrashBacktrace` | Transient | Created on `backtraceReporter` access | Could be cached (see finding #3) |
| Static encoder/decoder | Process | `CrashReportingFeature` class | Never deallocated |

The main memory concern is `CrashContext` copies (see finding #2) and the
`RUMViewEvent` stored in `CrashContextCoreProvider`. A single `RUMViewEvent` can be
substantial due to its deeply nested structure (~50+ fields).

---

## Priority ranking

| # | Finding | Impact | Effort | Priority |
|---|---------|--------|--------|----------|
| 1 | Coalesce context encoding | High — CPU + memory on hot path | Medium | **P0** |
| 2 | Reduce CrashContext copying | Medium — transient allocations | Medium | **P1** |
| 6 | Batch provider updates | Medium — reduces Task churn | Medium | **P1** |
| 7 | AsyncStream instead of Task-per-change | Medium — allocation reduction | Low | **P1** |
| 3 | Cache backtraceReporter | Low — called infrequently | Trivial | **P2** |
| 4 | Move encoder/decoder to actor | Low — correctness improvement | Trivial | **P2** |
| 5 | Filter pipeline allocations | Negligible — cold path | N/A | **Won't fix** |

---

## References

- `ModernConcurrency.md` — concurrency patterns applied in this module
- `StateOfTheMigration.md` — current Swift 6 migration status
- `DatadogInternal/Resources/TODO.md` — AsyncStream message bus migration plan
