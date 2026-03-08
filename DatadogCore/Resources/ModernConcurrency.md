# Modern Concurrency Migration Guide — DatadogCore

Patterns and lessons learned from migrating `DatadogCore` to Swift 6.
DatadogCore is the **infrastructure backbone** of the SDK — it owns the storage pipeline,
upload workers, context provider, and message bus. Unlike feature modules (Logs, RUM),
Core does **not** naturally belong on `@MainActor` and performs heavy I/O; most of its
concurrency stays queue-based with targeted `Sendable` fixes.

See also: `docs/ModernConcurrency.md` for cross-cutting lessons.

---

## 1. DatadogCore is NOT `@MainActor`

DatadogCore performs file I/O, network uploads, data encryption, and orchestrates
background threads. Making it `@MainActor` would block the main thread and violate
the SDK's "small footprint" philosophy.

**Exception:** `Datadog.initialize()` is called via `runOnMainThreadSync` because
`DatadogContextProvider` reads UIKit state and subscribes to notifications on init.
This stays as-is — the `@MainActor` is implicit in the call site, not the Core class.

---

## 2. DispatchQueues stay — Core's queues are I/O-bound

DatadogCore's queues are **not** simple state serializers — they coordinate disk I/O,
network uploads, and batch lifecycle. Converting them to actors would:

- Force all storage and upload paths to be `async`, adding overhead with no benefit
- Break the `flush()` mechanism which relies on `queue.sync {}` for test determinism
- Require restructuring the entire `DataUploadWorker` scheduling (asyncAfter + work items)

| Queue | Purpose | Decision |
|-------|---------|----------|
| `readWriteQueue` | Serializes file reads/writes across all features | **Keep** — I/O-bound, blocking sync reads needed |
| `MessageBus.queue` | Serializes message dispatch to receivers | **Keep** — fire-and-forget messages, sync flush needed |
| `DatadogContextProvider.queue` | Serializes context reads/writes | **Keep** — sync reads needed for `eventWriteContext` |
| `DataUploadWorker.queue` | Schedules upload cycles with delay/jitter | **Keep** — `asyncAfter` + `DispatchWorkItem` cancellation |
| `FeatureUpload.uploadQueue` | Per-feature upload worker queue | **Keep** — created during feature registration |
| `FeatureDataStore.queue` | Serializes data store I/O | **Keep** — file I/O with sync flush needed |

**Takeaway:** Actors are for protecting mutable state with compiler guarantees; Core's
queues protect I/O pipelines where synchronous blocking is required for correctness
and test determinism.

---

## 3. `Sendable` conformances for internal types

Core's internal types are captured in `DispatchQueue.async` closures which are
`@Sendable` in Swift 6. The fix is to make these types `Sendable` or `@unchecked Sendable`.

### Types made `@unchecked Sendable`

| Type | Justification |
|------|---------------|
| `FeatureStorage` | Struct with immutable properties; `queue`, `encryption`, `telemetry` are safe across threads |
| `FeatureDataStore` | Class with queue-based serialization (`queue.async/sync`); all mutable state accessed only on `queue` |
| `DatadogCore` | Class with `ReadWriteLock`-protected registries and queue-based context; state is already thread-safe |
| `CITestIntegration` | Immutable after init (`let` properties); static `active` is set once at startup |

### Protocols made `Sendable`

| Protocol | Justification |
|----------|---------------|
| `FilesOrchestratorType` | Stored in `FileWriter: Writer` (which is `Sendable`); implementations use `ReadWriteLock` |
| `DataEncryption` | Stored in `FileWriter`; implementations are typically stateless or thread-safe |

---

## 4. `ContextValueReceiver` becomes `@Sendable`

The `ContextValueReceiver<Value>` typealias is a closure captured across queue boundaries
(e.g. `NWPathMonitor.pathUpdateHandler`, `OperationQueue.main.addOperation`). Making it
`@Sendable` satisfies Swift 6's closure capture checks:

```swift
// Before
internal typealias ContextValueReceiver<Value> = (Value) -> Void

// After
internal typealias ContextValueReceiver<Value> = @Sendable (Value) -> Void
```

This propagates to all publishers (`LowPowerModePublisher`, `NetworkConnectionInfoPublisher`,
`ApplicationStatePublisher`, etc.) — their `publish(to:)` closures are now `@Sendable`.

**Impact:** Callers that store `ContextValueReceiver` need not change if their closures
already capture only Sendable values (which they do — they write to queue-protected state).

---

## 5. Global mutable state fixes

Swift 6 forbids mutable global state without explicit concurrency safety.

| Global | Problem | Fix |
|--------|---------|-----|
| `ContextSharingFeature.name` | `static var` → mutable global | Change to `static let` (it's never mutated) |
| `CrossPlatformExtension.contextSharingTransformer` | `static var` → mutable global | `nonisolated(unsafe)` — accessed only from Obj-C entry points; adding actor isolation would break the `@objc` API |
| `CITestIntegration.active` | `static let` of non-Sendable type | Make `CITestIntegration: @unchecked Sendable` — immutable after init |
| `registerObjcExceptionHandlerOnce` | `let` closure not concurrency-safe | `nonisolated(unsafe)` — called once during `initialize()`, always on main thread |

---

## 6. `TLVBlockError.invalidDataType(got: Any)` fix

The `Any` associated value is not `Sendable`. Since this error case is only used for
diagnostics, wrapping it in `String(describing:)` at the throw site and storing a `String`
instead is the cleanest fix:

```swift
// Before
case invalidDataType(got: Any)

// After
case invalidDataType(description: String)
```

---

## 7. `FileWriter` Sendable conformance (via protocols)

`FileWriter` conforms to `Writer: Sendable` but stores `FilesOrchestratorType` and
`DataEncryption?` which are not `Sendable`. The fix is to make these protocols `Sendable`:

- `FilesOrchestratorType: Sendable` — implementations (`FilesOrchestrator`) use
  `ReadWriteLock` for thread safety and are already `@unchecked Sendable`
- `DataEncryption: Sendable` — this is defined in `DatadogInternal` (Swift 5 mode);
  adding `: Sendable` there doesn't break existing conformers

---

## 8. `AsyncWriter` removed — queue dispatch folded into `FileWriter`

`AsyncWriter` was a thin wrapper that dispatched `Writer.write` calls to a
`DispatchQueue`. Rather than adding `Sendable` constraints to its generic captures,
the struct was eliminated entirely:

- **`FileWriter`** gained an optional `queue: DispatchQueue?` parameter. When set,
  `write` dispatches the I/O work to that queue; otherwise it executes synchronously.
- **`FeatureStorage.writer(for:)`** now returns `FileWriter` directly (passing the
  `readWriteQueue`) instead of wrapping it in `AsyncWriter`.
- **`NOPWriter`** was moved into `FileWriter.swift`.
- **`AsyncWriter.swift`** was deleted along with its pbxproj references.

---

## 9. `BackgroundTaskCoordinator` — `@MainActor` protocol methods

`UIApplication.beginBackgroundTask(expirationHandler:)` and `endBackgroundTask(_:)`
are `@MainActor`-isolated. The `@preconcurrency` conformance on `UIApplication`
suppresses the compile-time diagnostic but Swift 6 **runtime** enforcement still
traps when called off the main thread.

Since `DataUploadWorker` is an actor running on the cooperative thread pool, its
calls to `backgroundTaskCoordinator?.beginBackgroundTask()` would crash at runtime.

**Fix:** Make `BackgroundTaskCoordinator` protocol methods `@MainActor`-isolated.
Call sites in `DataUploadWorker.performUploadCycle()` use `await` to hop to the
main actor only when needed. This is idiomatic Swift concurrency — if the caller
is already on the main thread, no context switch occurs.

---

## 10. Clean up `#if swift(>=5.9)` checks

With Swift 6 as the language mode, `swift(>=5.9)` is always true. Three locations
in DatadogCore use this pattern:

| File | Before | After |
|------|--------|-------|
| `Datadog.swift:260` | `#if swift(>=5.9) && os(visionOS)` | `#if os(visionOS)` |
| `DatadogCore.swift:547` | `!(swift(>=5.9) && os(visionOS))` | `!os(visionOS)` |
| `CarrierInfoPublisher.swift:10` | `!(swift(>=5.9) && os(visionOS))` | `!os(visionOS)` |

---

## 11. `flush()` and `Flushable` — no change needed

Unlike feature modules where removing a queue can make `flush()` dead code, Core's
queues remain. `flush()` stays essential for test determinism:

```swift
extension DatadogCore: Flushable {
    func flush() {
        // Repeated to catch operations spawned from other operations
        for _ in 0..<5 {
            bus.flush()           // queue.sync {}
            features.forEach { $0.flush() }
            contextProvider.flush() // queue.sync {}
            readWriteQueue.sync {}
        }
    }
}
```

No changes needed here.

---

## 12. `@preconcurrency import` for DatadogInternal

`DatadogInternal` compiles in Swift 5 mode and has types with mutable global state
(`ObjcException.rethrow`) that cannot be fixed from DatadogCore. Using
`@preconcurrency import DatadogInternal` in `DatadogCore.swift` downgrades
cross-module Sendable errors to warnings:

```swift
@preconcurrency import DatadogInternal
```

This is a temporary measure until `DatadogInternal` itself migrates to Swift 6.

---

## 13. `WritableKeyPath` is not `Sendable`

`WritableKeyPath` does not conform to `Sendable` in Swift 6. When a key path is
captured in a `@Sendable` closure (e.g. in `DatadogContextProvider.subscribe`),
use `nonisolated(unsafe)` to suppress the diagnostic:

```swift
func subscribe<Publisher>(_ keyPath: WritableKeyPath<DatadogContext, Publisher.Value>, to publisher: Publisher) {
    nonisolated(unsafe) let keyPath = keyPath
    let subscription = publisher.subscribe { [weak self] value in
        self?.write { $0[keyPath: keyPath] = value }
    }
    // ...
}
```

This is safe because the key path is a compile-time constant captured immutably.

---

## 14. Obj-C bridge types and `@unchecked Sendable`

When a struct bridges an Obj-C protocol to conform to `DataEncryption: Sendable`,
the Obj-C protocol type is not `Sendable`. Use `@unchecked Sendable` on the bridge:

```swift
internal struct DDDataEncryptionBridge: DataEncryption, @unchecked Sendable {
    let objcEncryption: objc_DataEncryption  // Obj-C protocol, not Sendable
    // ...
}
```

This is safe because:
- The stored value is `let` (immutable after init)
- The bridge is created once and doesn't mutate

---

## 15. ContextValuePublisher → ContextValueSource (AsyncStream)

The old callback-based `ContextValuePublisher` protocol has been replaced with a
simpler `ContextValueSource` protocol that uses `AsyncStream`:

```swift
internal protocol ContextValueSource: Sendable {
    associatedtype Value
    var initialValue: Value { get }
    var values: AsyncStream<Value> { get }
}
```

### What changed

| Before | After |
|--------|-------|
| `ContextValuePublisher` protocol with `publish(to:)` and `cancel()` | `ContextValueSource` with `initialValue` and `values: AsyncStream` |
| `ContextValueSubscription` / `ContextValueBlockSubscription` | `Task<Void, Never>` — cancellation is automatic |
| `DatadogContextProvider.subscribe(keyPath, to:)` | `DatadogContextProvider.observe(source) { $0.field = $1 }` |
| "Set" publishers (UserInfo, AccountInfo, Consent, AppVersion) | Direct `contextProvider.write { ... }` — no publisher needed |
| `ContextValueReceiver<Value>` typealias | Removed — closures are `@Sendable (inout DatadogContext, Value) -> Void` |

### Why this is better for Swift 6

1. **`WritableKeyPath` eliminated** — `WritableKeyPath` is not `Sendable`, forcing
   `nonisolated(unsafe)` hacks. The new `update` closure is `@Sendable` natively.
2. **No protocol boilerplate** — Removed `ContextValueSubscription`,
   `ContextValueBlockSubscription`, `AnyContextValuePublisher`, `NOPContextValuePublisher`.
3. **"Set" publishers removed** — `UserInfoPublisher`, `AccountInfoPublisher`,
   `TrackingConsentPublisher`, `ApplicationVersionPublisher` only existed to bridge
   imperative `set` calls to the context. Direct `contextProvider.write` is simpler
   and provides atomic read-modify-write semantics.
4. **Automatic lifecycle** — `AsyncStream.Continuation.onTermination` handles cleanup
   (removing notification observers, cancelling NWPathMonitor, etc.) when the
   consuming `Task` is cancelled.

### Example: before and after

**Before:**
```swift
contextProvider.subscribe(\.networkConnectionInfo, to: NWPathMonitorPublisher())
```

**After:**
```swift
contextProvider.observe(NWPathMonitorSource()) { $0.networkConnectionInfo = $1 }
```

**Before (imperative set):**
```swift
userInfoPublisher.current = UserInfo(...)
```

**After:**
```swift
contextProvider.write { $0.userInfo = UserInfo(...) }
```

### ContextSharingTransformer

`ContextSharingTransformer` previously conformed to `ContextValuePublisher`. Since it
is used directly by `CrossPlatformExtension` (not through `DatadogContextProvider.subscribe`),
it keeps its own `publish(to:)` / `cancel()` methods without the protocol.

---

## 16. Future: Storage subsystem as actor (requires DatadogInternal migration)

The storage subsystem (`FeatureStorage`, `FilesOrchestrator`, `FileWriter`, `FileReader`,
`DataReader`) currently shares a single `readWriteQueue` for serializing all file I/O.
This is correct but relies on `@unchecked Sendable` and external queue discipline.

The ideal end state is a **StorageActor** that unifies orchestration and I/O:

```
Current:
  FeatureStorage (@unchecked Sendable, struct)
    ├── FilesOrchestrator (@unchecked Sendable, class) ← mutable state
    ├── FileWriter (struct) ← dispatches to readWriteQueue
    ├── FileReader (class, @unchecked Sendable) ← mutable filesRead set
    └── DataReader (class) ← dispatches to readWriteQueue

Future:
  StorageActor (actor)
    ├── orchestration logic (file lifecycle, purging, metrics)
    ├── write logic (encode, encrypt, append)
    └── read logic (decode, decrypt, batch marking)
```

### Why this is blocked

- **`Writer` protocol** lives in `DatadogInternal` and is synchronous. Making
  `Writer.write` async would touch every feature module (RUM, Logs, Trace,
  SessionReplay, CrashReporting, Flags, Profiling — 25+ call sites).
- **`eventWriteContext` closure** would need to become `async`, propagating
  through `FeatureScope` and all feature modules.
- **`MessageBus`** — receivers that call `writer.write` in `receive(message:from:)`
  would also need to become async.

### When to do this

This should be done as part of the **DatadogInternal Swift 6 migration**, when
`Writer`, `FeatureScope`, and `FeatureMessageReceiver` can all be updated to
async interfaces in a single coordinated pass across all modules.

### What it unlocks

- Eliminates `DataReader` (queue wrapper around `FileReader`)
- Eliminates `queue` parameter on `FileWriter`
- Eliminates `@unchecked Sendable` on `FilesOrchestrator` and `FeatureStorage`
- Removes `@ReadWriteLock` on `pendingBatches` (actor isolation handles it)
- Compiler-verified data race safety for the entire storage pipeline

---

## 17. Future: MessageBus as actor (requires DatadogInternal migration)

`MessageBus` is a natural actor candidate — it holds mutable state (`bus`, `core`,
`configuration`) protected by a serial queue. Converting it is blocked by the same
`DatadogInternal` dependency:

- `FeatureMessageReceiver` is not `Sendable` (protocol in `DatadogInternal`)
- `FeatureMessage` and `DatadogCoreProtocol` are not `Sendable`
- `Flushable` conformance requires blocking sync (`queue.sync {}`)

This should also be addressed during the DatadogInternal migration.

---

## 18. Migration checklist for DatadogCore

1. ✅ Set `.swiftLanguageMode(.v6)` in `Package.swift`
2. ✅ Bump iOS deployment target to 13.0
3. ✅ Fix global mutable state errors (section 5)
4. ✅ Add `Sendable` conformances to internal types (section 3)
5. ✅ Make `ContextValueReceiver` `@Sendable` (section 4)
6. ✅ Make `FilesOrchestratorType` and `DataEncryption` protocols `Sendable` (section 7)
7. ✅ Fix `TLVBlockError.invalidDataType` (section 6)
8. ✅ Clean up `#if swift(>=5.9)` checks (section 9)
9. ✅ Add `@preconcurrency import DatadogInternal` (section 11)
10. ✅ Fix `WritableKeyPath` capture (section 12)
11. ✅ Fix Obj-C bridge Sendable conformance (section 13)
12. ✅ Replace ContextValuePublisher with ContextValueSource (section 14)
13. ✅ Remove AsyncWriter, fold queue dispatch into FileWriter (section 8)
14. ✅ Fix AppBackgroundTaskCoordinator @MainActor runtime crash (section 9)
15. ✅ Verify build compiles cleanly
16. ☐ Run tests and fix any test compilation issues
17. ☐ Fix deployment targets in `.xcodeproj` test targets to match `Package.swift`
18. ☐ Storage subsystem → actor (section 16, blocked on DatadogInternal)
19. ☐ MessageBus → actor (section 17, blocked on DatadogInternal)
