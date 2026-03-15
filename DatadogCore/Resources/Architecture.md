# DatadogCore — Architecture Review & Performance Findings

Analysis of the `DatadogCore` module after the Swift 6 structured concurrency migration.
Focus: memory efficiency, CPU overhead, and opportunities for improvement.

---

## Current Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       DatadogCore                           │
│                                                             │
│  ┌─────────────────────────┐   ┌──────────────────────┐    │
│  │  DatadogContextProvider  │   │      MessageBus       │    │
│  │  (actor)                 │   │      (actor)          │    │
│  │                          │   │                       │    │
│  │  9 AsyncStream Tasks     │   │  receivers: [String:  │    │
│  │  (context sources)       │   │   MessageReceiver]    │    │
│  └────────┬─────────────────┘   └───────────┬──────────┘    │
│           │ read() / write()                │ send()        │
│           ▼                                 ▼               │
│  ┌────────────────────────────────────────────────────┐     │
│  │              FeatureStore (NSLock)                  │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐         │     │
│  │  │Feature A │  │Feature B │  │Feature C │  ...     │     │
│  │  │(RUM)     │  │(Logs)    │  │(Trace)   │         │     │
│  │  └──┬───────┘  └──┬───────┘  └──┬───────┘         │     │
│  └─────┼─────────────┼─────────────┼──────────────────┘     │
│        ▼             ▼             ▼                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Storage  │  │ Storage  │  │ Storage  │  (per feature)    │
│  │ (actor)  │  │ (actor)  │  │ (actor)  │                   │
│  │          │  │          │  │          │                   │
│  │ 2 Orch.  │  │ 2 Orch.  │  │ 2 Orch.  │  (auth+unauth)  │
│  └──┬───────┘  └──┬───────┘  └──┬───────┘                  │
│     ▼             ▼             ▼                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Upload   │  │ Upload   │  │ Upload   │  (per feature)    │
│  │ Worker   │  │ Worker   │  │ Worker   │                   │
│  │ (actor)  │  │ (actor)  │  │ (actor)  │                   │
│  └──────────┘  └──────────┘  └──────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Finding 1: FileWriter created on every event write (Critical) — ✅ DONE

**Impact:** High memory churn, unnecessary Task creation  
**Location:** `FeatureStorage.writer(for:)` → `CoreFeatureScope.eventWriteContext()`

**Resolution:** Writers are now cached as `private lazy var authorizedWriter` and `private lazy var unauthorizedWriter` in `FeatureStorage`. The `writer(for:)` method is actor-isolated (no longer `nonisolated`) and returns the cached instance. This reduces `FileWriter` + `AsyncStream` + drain `Task` allocations from O(events) to O(1) per feature — exactly 2 `AsyncStream`s per feature (authorized + unauthorized).

---

## Finding 2: DatadogContext copied on every read (Moderate)

**Impact:** Moderate memory pressure under high write frequency  
**Location:** `DatadogContextProvider.read()`, `DatadogContextProvider.write()`

`DatadogContext` is a struct with ~25 fields including heap-allocated types (`String`, `[String: AdditionalContext]`, `AppStateHistory`, `UserInfo?`, `DeviceInfo`, etc.). Every `read()` produces a full copy. Every `write()` sends a copy to each receiver.

Current copy points per event write:
1. `eventWriteContext()` → `contextProvider.read()` → 1 copy
2. Context change → `write()` → 1 copy per receiver (MessageBus publisher)
3. MessageBus → `send(.context(context))` → 1 copy per `receive(message:)` call

### Recommendation

Short-term: No action needed. The struct is <1 KB and copy overhead is dwarfed by JSON encoding + file I/O costs on the write path.

Long-term: If `DatadogContext` grows or write frequency increases significantly, consider making it a reference type with copy-on-write semantics, or splitting into a "stable" part (site, clientToken, service — never changes) and a "dynamic" part (network, battery, consent — changes often).

---

## Finding 3: Three actor hops per event write (Moderate)

**Impact:** Scheduling overhead on the hot path  
**Location:** `CoreFeatureScope.eventWriteContext()`

The event write hot path requires:

| Hop | Actor | Purpose |
|-----|-------|---------|
| 1 | `DatadogContextProvider` | `read()` — get current context |
| 2 | `FeatureStorage` | `writer(for:)` — get writer for consent |
| 3 | `FilesOrchestrator` | `getWritableFile()` — in the drain Task |

Each actor hop involves a potential thread switch through the cooperative thread pool. Under load, these hops compete with other SDK work and app work on the shared executor.

### Recommendation

If Finding 1 (cached writer) is adopted, hop 2 disappears for steady-state writes (same consent level), reducing to 2 hops. This is the best practical improvement without restructuring the architecture.

Further reduction would require merging `DatadogContextProvider` into `DatadogCore` or passing context differently, which is a larger change.

---

## Finding 4: DataUploader blocks a thread with DispatchSemaphore (Moderate)

**Impact:** Wastes a thread from the cooperative pool during network I/O  
**Location:** `DataUploader.upload()` (line 59, 85)

`DataUploader.upload()` is synchronous — it uses `DispatchSemaphore` to block while waiting for `URLSession.dataTask` completion. Since `DataUploadWorker` is an actor, the blocked thread is from the cooperative thread pool, which has a limited number of threads (typically equal to CPU core count).

A long network request (e.g., high latency, large payload) holds a cooperative thread hostage, potentially starving other actors.

### Recommendation

Convert `DataUploader.upload()` to an async method using `URLSession.data(for:)` (available iOS 13+). This frees the thread during network wait:

```swift
func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) async throws -> DataUploadStatus {
    let request = try requestBuilder.request(for: events, with: context, execution: execution)
    let (_, response) = try await session.data(for: request)
    // ...
}
```

**Trade-off:** Requires `HTTPClient` protocol to gain an async method. The callback-based `send(request:completion:)` can coexist during migration.

---

## Finding 5: Task-per-message in MessageBus dispatch (Low)

**Impact:** Low but measurable allocation overhead  
**Location:** `DatadogCore.send(message:)` (line 336)

Every `send(message:)` creates a fire-and-forget `Task`:

```swift
func send(message: FeatureMessage) {
    Task { await bus.send(message: message) }
}
```

Context changes are published through the MessageBus, so every battery/network/app-state update creates a Task to deliver the `.context(...)` message. Under active use this can mean 10–20+ Tasks per second just for context propagation.

### Recommendation

This is acceptable overhead since `Task` creation is cheap (~microseconds). However, if profiling shows Task creation as a hotspot, consider:

1. Batching context updates with a debounce (e.g., coalesce updates within 100ms)
2. Using a dedicated `AsyncStream` channel between `DatadogContextProvider` and `MessageBus` instead of fire-and-forget Tasks

---

## Finding 6: Redundant context read when upload is blocked (Low)

**Impact:** Unnecessary actor hop + struct copy  
**Location:** `DataUploadWorker.performUploadCycle()`

```swift
private func performUploadCycle() async {
    let context = contextProvider.read()          // ← always reads
    let blockersForUpload = uploadConditions.blockersForUpload(with: context)
    let isSystemReady = blockersForUpload.isEmpty
    let files = isSystemReady ? fileReader.readFiles(limit: maxBatchesPerUpload) : nil
    // ...
}
```

Context is read every cycle even when upload conditions will block (low battery, no network, low power mode). The blocker check itself needs context, but a lightweight check could short-circuit the full read.

### Recommendation

This is a minor optimization. The context read is one actor hop per upload cycle (~every 2–20 seconds). Not worth optimizing unless upload cycles become significantly more frequent.

---

## Finding 7: flush() relies on DispatchSemaphore to block (Low)

**Impact:** Thread blocking, incompatible with strict Swift concurrency  
**Location:** `MessageBus.flush()`, `FeatureDataStore.flush()`

The `Flushable` protocol requires synchronous `flush()`. Both `MessageBus` and `FeatureDataStore` implement it with:

```swift
nonisolated func flush() {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await self.barrierFlush()
        semaphore.signal()
    }
    semaphore.wait()
}
```

This works but blocks a thread and is fragile — if called from an actor context, it can deadlock.

### Recommendation

Since `flush()` is only used in tests, this is acceptable. Long-term, the `Flushable` protocol should offer an `async` variant:

```swift
protocol Flushable {
    func flush()
    func flush() async
}
```

Test code can use `await flush()` directly.

---

## Finding 8: BackgroundTaskCoordinator ReadWriteLock is redundant (Low)

**Impact:** Unnecessary lock overhead  
**Location:** `AppBackgroundTaskCoordinator.currentTaskId`, `ExtensionBackgroundTaskCoordinator.currentActivity`

Both coordinators use `@ReadWriteLock` on their mutable state, but since `beginBackgroundTask()` and `endBackgroundTask()` are `@MainActor`-isolated, all access is serialized on the main thread. The lock is unnecessary.

### Recommendation

Remove `@ReadWriteLock` and use plain properties:

```swift
internal class AppBackgroundTaskCoordinator: BackgroundTaskCoordinator, @unchecked Sendable {
    private let app: UIKitAppBackgroundTaskCoordinator?
    private var currentTaskId: UIBackgroundTaskIdentifier?
    // ...
}
```

The `@unchecked Sendable` is still needed since the class is accessed from multiple isolation domains (stored in the actor, called on MainActor).

---

## Finding 9: Per-feature resource multiplication (Informational)

**Impact:** Linear scaling with number of features  
**Location:** `DatadogCore.register(feature:)`, `FeatureStorage`, `FeatureUpload`

Each remote feature (RUM, Logs, Trace, Session Replay, Crash Reporting) creates:

| Resource | Count per feature |
|----------|-------------------|
| `FeatureStorage` (actor) | 1 |
| `FilesOrchestrator` (actor) | 2 (authorized + unauthorized) |
| `FileWriter` drain Task | 1+ (see Finding 1) |
| `DataUploadWorker` (actor) | 1 |
| Upload loop Task | 1 |
| `FeatureDataStore` (actor) | 1 (per scope creation) |

With 5 remote features, that's at minimum **5 actors + 10 orchestrator actors + 5 upload actors + 5 upload Tasks + 5 drain Tasks = 30 concurrent entities**.

### Recommendation

This is by design — per-feature isolation prevents cross-feature contention and allows independent lifecycle management. The overhead is acceptable for the SDK's use case. No change recommended.

---

## Finding 10: CoreFeatureScope allocated per scope(for:) call (Low)

**Impact:** Small per-call allocation  
**Location:** `DatadogCore.scope(for:)`

```swift
func scope<Feature>(for featureType: Feature.Type) -> FeatureScope {
    return CoreFeatureScope<Feature>(in: self)
}
```

Each call allocates a new `CoreFeatureScope` (class) with a `FeatureDataStore` (actor). Features typically call `scope(for:)` once during initialization and cache the result, so this is not a hot path.

### Recommendation

No change needed. If profiling reveals frequent `scope(for:)` calls, a cache in `FeatureStore` keyed by feature name would eliminate repeated allocations.

---

## Summary: Priority ranking

| # | Finding | Impact | Effort | Recommendation |
|---|---------|--------|--------|----------------|
| 1 | FileWriter per event write | **High** | Low | ✅ Cached writer per consent in FeatureStorage |
| 2 | DatadogContext copies | Moderate | Medium | Monitor; split if context grows |
| 3 | Three actor hops per write | Moderate | Low | Addressed by Finding 1 (reduces to 2) |
| 4 | DataUploader semaphore block | Moderate | Medium | Convert to async URLSession.data(for:) |
| 5 | Task-per-message dispatch | Low | Medium | Acceptable; debounce if profiled |
| 6 | Context read when blocked | Low | Low | Minor; not worth optimizing |
| 7 | flush() semaphore pattern | Low | Low | Add async flush() variant for tests |
| 8 | Redundant ReadWriteLock | Low | Trivial | Remove locks on MainActor-isolated state |
| 9 | Per-feature multiplication | Info | N/A | By design; no change |
| 10 | Scope allocation per call | Low | Low | Cache if profiled |

---

## Actionable next steps

1. ~~**Implement Finding 1**~~ ✅ Done — cached `FileWriter` in `FeatureStorage` via `lazy var`.

2. ~~**Implement Finding 8**~~ ✅ Done — removed `@ReadWriteLock` from `BackgroundTaskCoordinator`.

3. ~~**Implement Finding 4**~~ ✅ Done — converted `DataUploader` to async `URLSession`.

4. ~~**Implement Finding 5**~~ ✅ Done — replaced Task-per-message with `AsyncStream` channel.

5. ~~**Implement Finding 7**~~ ✅ Done — added `async flush()` variant to `Flushable` protocol.
