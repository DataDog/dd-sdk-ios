# DatadogInternal / DatadogCore — Swift 6 Migration Status

Current state of the Swift 6 / modern concurrency migration for shared infrastructure
in `DatadogInternal` and `DatadogCore`.
Use this to pick up remaining work or as a reference when migrating other modules.

---

## Completed

### Swift 6 language mode for DatadogInternal

Moved `DatadogInternal` from Swift 5 to `.swiftLanguageMode(.v6)` with strict
concurrency checking. Raised minimum deployment target from iOS 12 to iOS 13.

See `ModernConcurrency.md` (same folder) for the full list of fixes:
- Nested enums/structs inside `Sendable` types given explicit conformance
- `@unchecked Sendable` for types with non-Sendable existentials (`AnyCodable`, `LogEventAttributes`, etc.)
- Generated RUM models changed from `Sendable` to `@unchecked Sendable`
- `@ReadWriteLock` static vars refactored to `static let` + computed property
- `nonisolated(unsafe)` for global mutable state protected by external locks
- Benchmark protocols made `Sendable`
- Obj-C bridge types made `@unchecked Sendable`

### Actor conversion: MessageBus

`MessageBus` converted from `final class` with `DispatchQueue` to a Swift **actor**.

- Receivers dispatched synchronously within actor isolation
- `DatadogCore` wraps bus calls in `Task { await ... }` (same fire-and-forget as old `queue.async`)
- `flush()` bridges to blocking via `nonisolated` + `DispatchSemaphore`
- Removed `AsyncDatadogFeature` protocol, `MockAsyncFeature`, per-feature continuations

See `TODO.md` (same folder) for the full MessageBus migration plan.

### Actor conversion: FilesOrchestrator (storage subsystem)

`FilesOrchestrator` converted from `class` to `actor`. `DataReader` wrapper eliminated.

- `FileWriter` — removed queue, encoding is synchronous, file I/O is async via actor
- `FileReader` — `readFiles(limit:)` and `markBatchAsRead(_:reason:)` are `async`
- `Reader` protocol — made `async`
- `FeatureStorage` — simplified, changed from `@unchecked Sendable` to `Sendable`
- `WritableFile`, `ReadableFile`, `StoragePerformancePreset` — made `Sendable`

See `ModernConcurrency.md` §11 for full details.

### Writer protocol made async

`Writer.write(value:)` changed from synchronous to `async`:

```swift
// Before
func write<T: Encodable, M: Encodable>(value: Event<T, M>) throws
// After
func write<T: Encodable, M: Encodable>(value: Event<T, M>) async
```

All 25+ call sites across feature modules updated to `await writer.write(value:)`.
`FileWriter` moved encoding to the call site (synchronous) with only file I/O dispatched
to the orchestrator actor.

### FeatureScope.eventWriteContext — async return instead of callback

Refactored from a callback-based API to an async function returning an optional tuple:

```swift
// Before
func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) async -> Void)
// After
func eventWriteContext(bypassConsent: Bool) async -> (DatadogContext, Writer)?
```

- **CoreFeatureScope** — directly returns `(context, writer)`, removed `DispatchSemaphore`
  and `Task` wrapper
- **Callers** — synchronous call sites (e.g. `Monitor.process`, `TelemetryReceiver.receive`)
  wrap in `Task { ... }` and use `guard let (context, writer) = await ... else { return }`
- **Mocks** — `PassthroughCoreMock`, `FeatureScopeMock`, `DatadogCoreProxy` updated to
  return the tuple directly

#### Sendable conformances added for eventWriteContext migration

To satisfy Swift 6's strict `sending` parameter checks on `Task.init` closures:

| Type | Module | Conformance | Reason |
|------|--------|-------------|--------|
| `CrashReportReceiver` | DatadogRUM | `@unchecked Sendable` | Struct captured in `Task` |
| `Monitor` | DatadogRUM | `@unchecked Sendable` | Class captured in `Task` |
| `TelemetryReceiver` | DatadogRUM | `@unchecked Sendable` | Class with `Task` wrappers |
| `WebViewEventReceiver` | DatadogRUM | `@unchecked Sendable` | Class with `Task` wrappers |
| `WatchdogTerminationReporter` | DatadogRUM | `@unchecked Sendable` | Class with async send |
| `FatalAppHang` | DatadogRUM | `@unchecked Sendable` | Struct captured in `Task` |
| `LogMessageReceiver` | DatadogLogs | `@unchecked Sendable` | Struct captured in `Task` |
| `WebViewLogReceiver` | DatadogLogs | `@unchecked Sendable` | Struct captured in `Task` |
| `LazySpanWriteContext` | DatadogTrace | `@unchecked Sendable` | Class with async method |

#### Non-Sendable JSON workaround

`WebViewEventReceiver` uses `typealias JSON = [String: Any]`, which is non-Sendable due
to `Any`. Introduced `SendableJSON` wrapper struct (`@unchecked Sendable`) to safely pass
events into `Task` closures. `WebViewLogReceiver` uses `nonisolated(unsafe) var` for its
event capture.

### Actor conversion: DatadogContextProvider

`DatadogContextProvider` converted from `final class @unchecked Sendable` with
`DispatchQueue` to a Swift **actor**.

- **Removed:** `queue` property, `defaultQueue` static, `Flushable` conformance,
  `read(block:)` callback overload
- **Renamed:** `observe(_:update:)` → `subscribe(to:update:)`
- **`write(block:)`** — closure parameter now `@Sendable`
- **`ContextValueSource.Value`** — now requires `Sendable` (consistent with
  `AsyncStream<Value>` requirements in Swift 6)
- **Convenience init** → `static func create(...)` factory method (actors don't
  support `convenience init`). Sources are constructed before the `Task` boundary
  to avoid capturing non-Sendable parameters.
- **DatadogCore callers** — all `contextProvider.write/read/publish` calls wrapped
  in `Task` or use `await`. `contextProvider.flush()` removed from the flush cycle
  (actor serialization replaces it).
- **DataUploadWorker** — `contextProvider.read()` calls now use `await`.

#### FeatureScope.context — parameter made @Sendable

`FeatureScope.context(_ block:)` and `dataStoreContext(_ block:)` closure parameters
changed to `@Sendable` to allow safe capture in `Task` closures:

```swift
// Before
func context(_ block: @escaping (DatadogContext) -> Void)
// After
func context(_ block: @escaping @Sendable (DatadogContext) -> Void)
```

Updated in protocol, `NOPFeatureScope`, `CoreFeatureScope`, and all mock implementations.

#### Sendable conformances added for DatadogContextProvider migration

| Type | Module | Conformance | Reason |
|------|--------|-------------|--------|
| `LocaleInfo` | DatadogInternal | `Sendable` | Required by `ContextValueSource.Value: Sendable` |
| `AppStateHistory` | DatadogInternal | `Sendable` | Required by `ContextValueSource.Value: Sendable` |
| `BacktraceReport` | DatadogInternal | `Sendable` | Required by `AppHang: Sendable` |
| `AppHang` | DatadogRUM | `Sendable` | Captured in `@Sendable` closure via `rumDataStoreContext` |

#### RUMMonitorProtocol.currentSessionID — completion made @Sendable

`currentSessionID(completion:)` closure parameter changed to `@Sendable` across protocol,
`Monitor`, `NOPRUMMonitor`, and Obj-C bridge.

### Tests migrated

- `DatadogContextProviderTests` — all tests converted to `async`; `subscribe(to:)` replaces
  `observe()`; `await provider.read()` replaces sync `read()`; thread safety test uses
  `withTaskGroup` instead of `callConcurrently`
- `DatadogTests` — 12 functions updated to `async`; `await` on `contextProvider.read()`
- `DatadogConfigurationTests` — 17 functions updated to `async throws`
- `DatadogCoreTests` — 7 functions updated to `async`; removed `contextProvider.flush()`
- `DDDatadogTests` — 3 functions updated to `async`
- `InternalProxyTests` — 1 function updated to `async throws`
- `FeatureContextTests` — 1 function updated to `async throws`
- `SpanWriteContextTests` — tests updated to `async` for new `spanWriteContext()` API

### FeatureStore — thread-safe feature registry

Introduced `FeatureStore` as a dedicated component to manage `features` and `stores`
dictionaries previously held directly by `DatadogCore`.

- **Architecture decision:** `FeatureStore` is a `final class: @unchecked Sendable` with
  `NSLock`, not an actor. `DatadogFeature` is not `Sendable`, so actor-isolated methods
  cannot return feature instances across isolation boundaries under Swift 6 rules.
- `DatadogCore` delegates `register(feature:)`, `get(feature:)`, `scope(for:)` to
  `FeatureStore` instead of managing dictionaries directly
- Thread-safe access via `lock.lock()` / `defer { lock.unlock() }`

### Actor conversion: FeatureDataStore

`FeatureDataStore` converted from `final class: @unchecked Sendable` with `DispatchQueue`
to a Swift **actor**.

- Removed `queue: DispatchQueue` property and initializer parameter — actor isolation
  provides serialization
- `directoryPath` marked `nonisolated let` (immutable, no isolation needed)
- `DataStore` protocol methods (`setValue`, `value`, `removeValue`, `clearAllData`) are
  `nonisolated` and bridge to actor-isolated private methods via `Task { await ... }`
- `flush()` uses `nonisolated` + `DispatchSemaphore` to block until actor mailbox drains
- Updated all call sites in `FeatureStore`, `DatadogCore`, and `CoreFeatureScope`

### Actor conversion: FeatureStorage

`FeatureStorage` converted from `struct: Sendable` with `DispatchQueue` to a Swift **actor**.

- Removed `queue: DispatchQueue` property and initializer parameter — actor isolation
  replaces `queue.async` for file operations
- `migrateUnauthorizedData`, `clearUnauthorizedData`, `clearAllData` are actor-isolated
  (previously dispatched via `queue.async`)
- `writer(for:)` and `reader` are `nonisolated` — they construct new value types from
  immutable (`let`) state only
- `setIgnoreFilesAgeWhenReading(to:)` remains `async` (delegates to `FilesOrchestrator` actors)
- Each feature now has independent serialization, eliminating cross-feature contention
  from the shared queue

### readWriteQueue removed from DatadogCore

The shared `DispatchQueue` (`com.datadoghq.ios-sdk-read-write`) has been fully removed
from `DatadogCore`. Its responsibilities are now handled by actor isolation:

| Previous usage | Replacement |
|---------------|-------------|
| `FeatureStorage` file ops (`queue.async`) | `FeatureStorage` actor isolation |
| `FeatureDataStore` data ops | `FeatureDataStore` actor isolation |
| `flush()` barrier (`queue.sync {}`) | Removed — actors serialize their own work |
| `mostRecentModifiedFileAt` (`queue.sync`) | Direct file access (reads `coreDirectory`, no feature contention) |
| Legacy V1 folder deletion (`queue.async`) | `Task.detached(priority: .utility)` |

### @MainActor on feature enable() methods

All public `enable()` methods annotated with `@MainActor` and wrapped in
`runOnMainThreadSync` for belt-and-suspenders main-thread enforcement:

```swift
@MainActor
public static func enable(with configuration: Configuration, in core: DatadogCoreProtocol) {
    runOnMainThreadSync {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }
}
```

Applied to:
- `Logs.enable()`, `RUM.enable()`, `Trace.enable()`, `Flags.enable()`
- `SessionReplay.enable()`, `CrashReporting.enable()`, `WebViewTracking.enable()`
- `URLSessionInstrumentation.enable()`
- All corresponding Obj-C bridge classes (`objc_Logs`, `objc_RUM`, etc.) marked `@MainActor`

### Actor conversion: NetworkInstrumentationFeature

`NetworkInstrumentationFeature` converted from `final class: DatadogFeature` with
`DispatchQueue` to a Swift **actor**.

- Removed `queue: DispatchQueue` property — actor isolation serializes the
  `interceptions` dictionary
- `messageReceiver`, `networkContextProvider` marked `nonisolated(unsafe) let`
  (protocols are not `Sendable`)
- `handlers`, `swizzlers`, `registeredDelegateClasses` — replaced `@ReadWriteLock`
  with `NSLock` + `nonisolated` computed properties (synchronous access required
  from swizzler callbacks for trace header injection in `interceptResume`)
- `interceptions` dictionary — purely actor-isolated (replaces `queue.async` dispatch)
- Swizzler callback entry points (`interceptTask`, `taskDidReceive`,
  `taskDidFinishCollecting`, `taskDidComplete`) are `nonisolated` — capture
  time-sensitive values (e.g. `Date()`) on the caller thread, then dispatch to
  actor-isolated private methods via `Task { await ... }`
- `flush()` uses `nonisolated` + `DispatchSemaphore` to drain actor mailbox

#### Sendable conformances added for NetworkInstrumentationFeature

| Type | Module | Conformance | Reason |
|------|--------|-------------|--------|
| `ImmutableRequest` | DatadogInternal | `Sendable` | Struct passed into `Task` closures |
| `FirstPartyHosts` | DatadogInternal | `Sendable` | Struct passed into `Task` closures |
| `TraceContext` | DatadogInternal | `Sendable` | Struct passed into `Task` closures |
| `TrackingMode` | DatadogInternal | `Sendable` | Enum passed into `Task` closures |
| `SamplingPriority` | DatadogInternal | `Sendable` | Enum in `TraceContext` |
| `SamplingMechanismType` | DatadogInternal | `Sendable` | Enum in `TraceContext` |
| `GraphQLRequestAttributes` | DatadogInternal | `Sendable` | Struct passed into `Task` closures |
| `TracingHeaderType` | DatadogInternal | `Sendable` | Enum in `FirstPartyHosts` |
| `RequestInstrumentationContext` | DatadogInternal | `@unchecked Sendable` | Contains non-Sendable `URLSessionHandlerCapturedState?` |
| `NetworkContextCoreProvider` | DatadogInternal | `@unchecked Sendable` | Class with `@ReadWriteLock`, non-Sendable protocols |

### Actor conversion: ViewHitchesReader

`ViewHitchesReader` converted from `final class: @unchecked Sendable` with
`DispatchQueue` to a Swift **actor**.

- Removed `queue: DispatchQueue` — replaced with `NSLock` for all state access
- All mutable state is `nonisolated(unsafe) private var` with underscore-prefixed names
- `config` is `nonisolated let` (immutable)
- `dataModel`, `telemetryModel`, `isActive` — `nonisolated` computed properties
  with lock-protected reads
- `stop()`, `didUpdateFrame(link:)` — `nonisolated` methods with lock-protected writes
- **No actor isolation used for state** — both the write path (`didUpdateFrame`,
  called synchronously from `CADisplayLink` `@objc` callback) and the read paths
  (`dataModel`, `telemetryModel`, called synchronously from `RUMViewScope.process()`)
  require `nonisolated` access
- Tests required zero modifications — synchronous lock replaces `queue.async`/`queue.sync`
- Removing the locks requires making `RUMScope.process()` async (see `TODO.md` Phase 8)

### Patterns established

- **Actor for context provider** — `DatadogContextProvider` uses actor isolation instead
  of `DispatchQueue` with concurrent reads / barrier writes. All access is serialized.
- **Static factory for actor init** — actors don't support `convenience init`, so
  `DatadogContextProvider.create(...)` is a `static func` that creates the actor and
  kicks off source subscriptions in a `Task`.
- **Construct sources before Task boundary** — context value sources (which conform to
  `Sendable`) are constructed synchronously before the `Task`, avoiding capturing
  non-Sendable factory parameters (`serverDateProvider`, `appLaunchHandler`, etc.).
- **`@Sendable` closures for cross-isolation callbacks** — `FeatureScope.context(_:)`,
  `dataStoreContext(_:)`, and `rumDataStoreContext(_:)` accept `@Sendable` closures
  so they can be safely dispatched from `Task` contexts.
- **Async return replaces callback** — `eventWriteContext` returns
  `(DatadogContext, Writer)?` directly instead of calling a block, letting callers
  use `guard let` pattern for cleaner control flow.
- **NSLock class for non-Sendable managed state** — when an actor must return
  non-Sendable types (e.g. `DatadogFeature`), use a `final class: @unchecked Sendable`
  with `NSLock` instead (as done in `FeatureStore`).
- **Nonisolated bridging for sync protocols** — when a protocol requires synchronous
  methods but the type is an actor, mark methods `nonisolated` and dispatch to
  actor-isolated private methods via `Task { await ... }` (as done in `FeatureDataStore`
  and `FeatureStorage`).
- **DispatchSemaphore for actor flush** — `nonisolated func flush()` blocks via
  `DispatchSemaphore` + `Task { await _drain(); sem.signal() }` to drain the actor
  mailbox synchronously (as done in `FeatureDataStore`).
- **NSLock on actor for fully-synchronous callers** — when both write and read paths
  are synchronous (e.g. `ViewHitchesReader`: writes from `CADisplayLink`, reads from
  `RUMViewScope.process()`), all state is `nonisolated(unsafe)` + `NSLock`. The actor
  provides `Sendable` but the lock does all synchronization. This is a stepping stone
  until the calling protocol (`RUMScope.process()`) becomes async.
- **Nonisolated + Task for time-sensitive callbacks** — when a synchronous callback
  must capture a timestamp on the caller thread (e.g. network interception start/end
  times), use a `nonisolated` entry point that captures time-sensitive values, then
  dispatches to an actor-isolated method via `Task { await ... }` for state updates
  (as done in `NetworkInstrumentationFeature`).

---

## Remaining

### DatadogCore as an actor

`DatadogCore` itself is still a `final class` with `@unchecked Sendable`. The
`readWriteQueue` has been removed. Remaining considerations:

| Item | Notes |
|------|-------|
| `flushAndTearDown()` uses `DispatchSemaphore` | Blocking API required by test infrastructure |
| `scope(for:)` is synchronous | Returns `CoreFeatureScope` synchronously; may need to stay that way |
| Feature registration | `register(feature:)` / `get(feature:)` go through `FeatureStore` (NSLock class) |
| `DatadogFeature` not `Sendable` | Blocks actor conversion for `FeatureStore` and `DatadogCore` |

### FeatureMessageReceiver protocol ✅

The protocol has been simplified from `receive(message:from:) -> Bool` to
`receive(message:)` (void return). The `from core:` parameter, `-> Bool` return,
`@discardableResult`, and `else fallback:` on `MessageSending.send()` have all
been removed. `CombinedFeatureMessageReceiver` now forwards to all receivers
(no short-circuit). Receivers that needed core access now inject `FeatureScope`
at construction time.

See `TODO.md` (same folder) for the full migration history.

### Remaining Sendable gaps

| Type | Module | Notes |
|------|--------|-------|
| `DatadogFeature` protocol | DatadogInternal | Not `Sendable`; blocks `FeatureStore` actor conversion |
| `AdditionalContext` protocol | DatadogInternal | Not `Sendable`; forces `nonisolated(unsafe)` in `set(context:)` |
| `ServerDateProvider` protocol | DatadogCore | Not `Sendable`; constructed before Task boundary as workaround |
| `AppLaunchHandling` protocol | DatadogCore | Not `Sendable`; same workaround |

### RUMScope.process() — make async to unlock actor isolation in scopes

See `TODO.md` Phase 8 for the full plan. Making `RUMScope.process()` async would
allow `ViewHitchesReader` (and other stateful scope components) to drop their `NSLock`
in favor of pure actor isolation.

### Flush mechanism

`DatadogCore.flush()` now iterates flushables without a queue barrier. With all storage
subsystems as actors, a unified async flush strategy (awaiting each actor's drain) would
provide stronger guarantees than the current loop.

---

## Not changing

| Item | Reason |
|------|--------|
| `DispatchSemaphore` in `flushAndTearDown()` | Blocking API required by test infrastructure |
| `FeatureMessageReceiver` remaining synchronous | ✅ Resolved — protocol simplified to `receive(message:)`, Phase 3–4 complete |
| `@unchecked Sendable` on `DatadogCore` | Can't be actor until `DatadogFeature` is `Sendable` |
| `FeatureStore` as class with NSLock | Can't be actor — must return non-Sendable `DatadogFeature` |
| `DatadogCoreProxy` context init | Uses `Task` to asynchronously read initial context from actor |

---

## Compilation status

All source modules build successfully with `.swiftLanguageMode(.v6)`:
- DatadogInternal
- DatadogCore
- DatadogRUM
- DatadogLogs
- DatadogTrace
- DatadogSessionReplay
- DatadogCrashReporting
- DatadogWebViewTracking
- DatadogFlags

Test targets require `DatadogSDKTesting` XCFramework for `build-for-testing`.
Source-only builds verified via both `xcodebuild` and `swift build`.

---

## Reference

- `ModernConcurrency.md` (same folder) — detailed patterns and decisions for DatadogInternal
- `TODO.md` (same folder) — MessageBus migration plan and phases
- `DatadogRUM/Resources/StateOfTheMigration.md` — RUM module migration status
- `DatadogLogs/Resources/StateOfTheMigration.md` — Logs module migration status
- `DatadogCrashReporting/Resources/StateOfTheMigration.md` — CrashReporting module migration status
- `DatadogWebViewTracking/docs/StateOfTheMigration.md` — WebViewTracking module migration status
- `Package.swift` — all modules use `.swiftLanguageMode(.v6)`
