# MessageBus Concurrency Migration Plan

## Context

The `MessageBus` was originally a `final class` using a `DispatchQueue` for
thread safety. The `FeatureMessageReceiver` protocol originally used a
synchronous callback with `core:` parameter and `Bool` return:

```swift
// BEFORE (removed)
public protocol FeatureMessageReceiver {
    @discardableResult
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool
}
```

This design forced features to use `DispatchQueue` + `@unchecked Sendable`
instead of Swift actors for state management. The protocol has since been
simplified (see "Current State" below).

## Current State

The `MessageBus` is now a Swift **actor**. The actor's isolation replaces the
`DispatchQueue` — receivers are dispatched synchronously within the actor.
Callers in `DatadogCore` wrap calls in `Task { await ... }` (same fire-and-forget
semantics as the old `queue.async`).

```swift
internal actor MessageBus {
    private var receivers: [String: FeatureMessageReceiver] = [:]

    func send(message: FeatureMessage) {
        receivers.values.forEach { $0.receive(message: message) }
    }
}
```

The `FeatureMessageReceiver` protocol has been simplified:

```swift
public protocol FeatureMessageReceiver {
    func receive(message: FeatureMessage)
}
```

- ✅ Removed `from core: DatadogCoreProtocol` parameter (RUM-3717)
- ✅ Removed `-> Bool` return type and `@discardableResult`
- ✅ Removed `else fallback:` from `MessageSending.send(message:)`
- ✅ `CombinedFeatureMessageReceiver` now forwards to all receivers (no short-circuit)
- ✅ Receivers that needed core access now inject `FeatureScope` at construction time

## Affected Modules

### Production Receivers (16 implementations)

| Module | Receiver | Notes |
|--------|----------|-------|
| DatadogCrashReporting | `CrashContextCoreProvider` | Could become an actor |
| DatadogRUM | `CrashReportReceiver` | Handles crash → RUM error conversion |
| DatadogRUM | `ErrorMessageReceiver` | Handles error messages |
| DatadogRUM | `WebViewEventReceiver` | WebView bridge events |
| DatadogRUM | `TelemetryReceiver` | Telemetry aggregation |
| DatadogRUM | `TelemetryInterceptor` | Telemetry filtering |
| DatadogRUM | `FlagEvaluationReceiver` | Feature flags |
| DatadogRUM | `WatchdogTerminationMonitor` | App termination tracking |
| DatadogLogs | `MessageReceivers` (2) | Log event handling |
| DatadogTrace | `MessageReceivers` | Span event handling |
| DatadogSessionReplay | `WebViewRecordReceiver` | WebView recording |
| DatadogSessionReplay | `RUMContextReceiver` | RUM context updates |
| DatadogInternal | `NetworkContextProvider` | Network instrumentation |
| DatadogCore | `ContextSharingTransformer` | Context sharing |
| DatadogProfiling | `AppLaunchProfiler` | Profiling integration |
| DatadogFlags | `FlagsFeature` | Feature flags |

### Features Using `CombinedFeatureMessageReceiver`

These compose multiple receivers. Short-circuit pattern has been removed —
all receivers now receive all messages via `forEach`:
- `RUMFeature`
- `LogsFeature`
- `SessionReplayFeature`

### Test Infrastructure

- `FeatureMessageReceiverMock`
- `TelemetryReceiverMock`
- `CrashReceiverMock`
- `PassthroughCoreMock`
- `SingleFeatureCoreMock`
- `MockFeature`

## Migration Strategy

### Phase 1: Sendable conformances ✅

1. ✅ Made `FeatureMessage`, `WebViewMessage`, `TelemetryMessage` `@unchecked Sendable`
   so they can cross isolation boundaries.
2. ✅ Added default `messageReceiver` on `DatadogFeature` (returns `NOPFeatureMessageReceiver`).

### Phase 2: Actor-based MessageBus ✅

Converted `MessageBus` from a `final class` with `DispatchQueue` to a Swift **actor**.
The actor's isolation replaces the queue — receivers are dispatched synchronously
within the actor, no streams or continuations needed.

1. ✅ `MessageBus` is now an `actor` with `receivers: [String: FeatureMessageReceiver]`.
2. ✅ `send(message:)` iterates receivers directly within actor isolation.
3. ✅ `DatadogCore` wraps bus calls in `Task { await ... }` (same fire-and-forget as old `queue.async`).
4. ✅ `flush()` bridges to blocking via `nonisolated` + `DispatchSemaphore`.
5. ✅ Removed `AsyncDatadogFeature` protocol and `MockAsyncFeature` — not needed.
6. ✅ Removed per-feature `AsyncStream.Continuation` management.

### Phase 3: Migrate Features (one at a time)

Migrate each module independently:
1. Convert `@unchecked Sendable` classes to actors where appropriate.
2. Update tests to use async patterns.

**Suggested order** (least to most complex):
1. `DatadogProfiling` — single simple receiver
2. `DatadogFlags` — single simple receiver
3. `DatadogCrashReporting` — `CrashContextCoreProvider` becomes actor
4. `DatadogTrace` — single receiver
5. `DatadogLogs` — two receivers
6. `DatadogSessionReplay` — two receivers
7. `DatadogRUM` — most receivers, highest complexity

**DatadogRUM progress:**
- ✅ `AppStateManager` — converted from `class` with `@ReadWriteLock` / `DispatchGroup`
  / `DispatchQueue` to a Swift `actor`. Eliminated all manual synchronization.
  Protocol `AppStateManaging: Sendable` with `async` methods.
- ✅ `WatchdogTerminationChecker` — `isWatchdogTermination(launch:)` converted from
  completion-based to `async`. Uses `withCheckedContinuation` to bridge
  `featureScope.context`.
- ✅ `WatchdogTerminationMonitor` — `@unchecked Sendable`; `sendWatchTerminationIfFound`
  and `sendWatchTermination` converted from completion-based to `async`. `start()` uses
  `Task { [weak self] in }`.
- ✅ `RUMAppLaunchManager` — `@unchecked Sendable`; `writeTTIDVitalEvent` uses
  `Task { [weak self] in await fetchAppStateInfo() }`. Extracts Sendable values
  (`activeViewUUID`, `activeViewPath`) from non-Sendable `RUMViewScope` before the
  Task boundary.
- ✅ `Monitor` — converted to lock-free `final class: @unchecked Sendable` with
  `AsyncStream` command pipeline. All mutable state (`attributes`, `debugging`,
  `scopes`) is only mutated inside the `for await` loop. See Phase 8 for details.
- ✅ All remaining receivers (`CrashReportReceiver`, `ErrorMessageReceiver`,
  `WebViewEventReceiver`, `TelemetryReceiver`, `TelemetryInterceptor`,
  `FlagEvaluationReceiver`) updated to new `receive(message:)` signature.
- See `DatadogRUM/Resources/StateOfTheMigration.md` for full details.

### Phase 4: Cleanup ✅

1. ✅ Removed `core:` parameter from `FeatureMessageReceiver.receive(message:)` (RUM-3717).
2. ✅ Removed `-> Bool` return type and `@discardableResult`.
3. ✅ Removed `else fallback:` from `MessageSending.send(message:)`.
4. ✅ `CombinedFeatureMessageReceiver` now forwards to all receivers (no short-circuit).
5. ✅ Receivers needing core access (`LogMessageReceiver`, `WebViewLogReceiver`,
   `AppLaunchProfiler`) now inject `FeatureScope` at construction time.
6. ✅ `MessageBus` no longer holds a `weak core` reference. `connect(core:)` removed.
7. ✅ `TelemetryReceiver` explicitly filters `UploadQualityMetric.name` to maintain
   the same behavior (previously achieved via `TelemetryInterceptor` returning `true`
   to short-circuit).

## Phase 5: Evaluate `DatadogCore` Actor Conversion

Several prerequisites for actor conversion have already been completed:

1. ✅ **`FeatureScope.eventWriteContext`** — already `async`, returning
   `(DatadogContext, Writer)?`. All feature modules use `await`.
2. ✅ **`readWriteQueue`** — removed from `DatadogCore` entirely (storage subsystem
   uses actor-isolated `FilesOrchestrator`).
3. ✅ **`MessageBus`** — already an actor (Phase 2).

**Open question: Does `DatadogCore` need to be an actor?**

The subsystems that needed isolation (`MessageBus`, `FilesOrchestrator`,
`DataUploadWorker`) are already actors. `DatadogCore` itself may work best as
a coordinator that owns these actors rather than being one itself. A single-actor
`DatadogCore` would serialize all access — including context reads, feature
registration, and message sending — which could hurt throughput compared to the
current design where subsystems operate independently.

**If actor conversion is pursued:**

1. **Add async overloads** to `DatadogCoreProtocol` for methods that mutate state
   (`register`, `send`, `set(context:)`, `set(anonymousId:)`).
2. **Replace `flush()` with async draining** — `flush()` relies on blocking
   mechanisms. An async `flush() async` or `withCheckedContinuation`-based approach
   is needed. Tests must migrate to `async` test methods.
3. **Evaluate the public API** — Customer-facing methods like `Datadog.setUserInfo()`
   are synchronous. Options:
   - Keep public API synchronous and use `Task { await core.setUserInfo(...) }` internally.
   - Provide async alternatives alongside sync ones (additive, non-breaking).

**Prerequisite:** ✅ Phases 3–4 are complete — the synchronous `FeatureMessageReceiver`
constraint has been removed.

## Phase 6: Convert Storage Subsystem to Actors ✅

Converted the storage subsystem from `DispatchQueue`-based serialization to
actor-based isolation:

1. ✅ **`FilesOrchestrator`** — converted from `class` to `actor`.
   - Removed `@unchecked Sendable`.
   - Removed `@ReadWriteLock` on `pendingBatches` (actor isolation replaces it).
   - Protocol `FilesOrchestratorType` methods are now `async`.
   - Added `setIgnoreFilesAgeWhenReading(_:)` method (actors cannot expose settable properties across boundaries).
   - Added `barrier()` for flush support.
   - Made `WritableFile`, `ReadableFile` protocols `Sendable`.
   - Made `StoragePerformancePreset` protocol `Sendable`.

2. ✅ **`FileWriter`** — uses `Task { await ... }` instead of `queue.async`.
   - Removed `queue` property entirely.
   - Encoding happens synchronously on the caller thread (avoids sending non-Sendable generic values across isolation).
   - Only the file I/O (getting writable file + appending) is async via the orchestrator actor.

3. ✅ **`FileReader`** — methods that interact with orchestrator are now `async`.
   - `readFiles(limit:)` is `async`.
   - `markBatchAsRead(_:reason:)` is `async`.
   - `readBatch(from:)` remains synchronous (pure I/O, no orchestrator interaction).

4. ✅ **`Reader` protocol** — made `async` (internal to `DatadogCore`).
   - `readFiles(limit:)` is `async`.
   - `markBatchAsRead(_:reason:)` is `async`.

5. ✅ **`DataReader`** — removed entirely.
   - Its only purpose was to serialize `FileReader` calls on `readWriteQueue`.
   - With async orchestrator, serialization is provided by the actor.

6. ✅ **`FeatureStorage`** — simplified.
   - `writer(for:)` creates `FileWriter` without a queue.
   - `reader` returns `FileReader` directly (no `DataReader` wrapper).
   - `setIgnoreFilesAgeWhenReading(to:)` is now `async`.
   - `@unchecked Sendable` removed (now plain `Sendable`).
   - Directory management methods (`migrateUnauthorizedData`, `clearAllData`, etc.) still use the queue for serialization.

7. ✅ **`DataUploadWorker`** — already an actor, trivially updated to `await` reader calls.

8. ✅ **`DatadogCore.flushAndTearDown()`** — bridges async `setIgnoreFilesAgeWhenReading` with `DispatchSemaphore`.

## Phase 7: Further Cleanup ✅

1. ✅ Make `Writer` protocol async (cascades into `FeatureScope.eventWriteContext`
   and all feature modules — 25+ call sites).
2. ✅ `readWriteQueue` removed from `DatadogCore` entirely.
3. ✅ `FeatureScope.eventWriteContext` is now `async` returning `(DatadogContext, Writer)?`.

## Phase 8: Monitor AsyncStream Command Pipeline ✅

Converted `Monitor` from a `class` with `NSLock` (`scopeProcessingLock`) and
`@ReadWriteLock` (attributes, debugging) to a lock-free `final class` using an
`AsyncStream` as the sole synchronization mechanism.

### Design

`Monitor` is `final class: @unchecked Sendable`. All mutable state (`attributes`,
`debugging`, `scopes`) is only mutated inside a single `for await` loop, so no locks
are needed. Public API methods are fire-and-forget — they yield commands to the stream
and return immediately. Processing happens on the cooperative thread pool.

```swift
internal final class Monitor: RUMCommandSubscriber, @unchecked Sendable {
    private var attributes: [AttributeKey: AttributeValue] = [:]
    private var debugging: RUMDebugging?
    private let commandContinuation: AsyncStream<RUMCommand>.Continuation

    func process(command: RUMCommand) {
        commandContinuation.yield(command)
    }

    private func processFromStream(command: RUMCommand) async {
        // Handle RUMGlobalAttributeCommand → mutate attributes
        // Handle RUMSetDebugCommand → mutate debugging
        // Handle RUMFlushCommand → resume continuation (test support)
        // Regular commands → set globalAttributes, process through scope tree
    }
}
```

### What changed

1. ✅ `scopeProcessingLock` (`NSLock`) — **removed**. The `for await` loop serializes
   command processing.
2. ✅ `@ReadWriteLock` on `attributes` — **removed**. Global attributes are now mutated
   via `RUMGlobalAttributeCommand` inside the processing loop. `addAttribute()`,
   `removeAttribute()`, etc. yield commands to the stream instead of directly mutating.
3. ✅ `@ReadWriteLock` on `debugging` — **removed**. Debug toggle is mutated via
   `RUMSetDebugCommand` inside the processing loop.
4. ✅ `globalAttributes` on commands — set inside `processFromStream` right before
   passing to the scope tree (single source of truth). Methods no longer snapshot
   attributes at call time.
5. ✅ `featureScope.set(context:)` — RUM context is eagerly computed inside the
   processing loop via `updateCoreContext()` after each command, eliminating the
   old closure that captured `scopes` and raced with processing.
6. ✅ `flush()` — uses `RUMFlushCommand` sentinel + `withCheckedContinuation` so
   tests can `await monitor.flush()` to synchronize.
7. ✅ Tests — `MonitorTests` and `Monitor+GlobalAttributesTests` converted to
   `async throws` with `await monitor.flush()` after command invocations.

### Why not an actor?

An actor was tried first but provided no benefit: every property and method had to be
marked `nonisolated` because the public `RUMMonitorProtocol` API is synchronous. The
actor's isolation boundary wasn't protecting anything — the `AsyncStream` was doing all
the serialization work. A plain class is simpler, avoids executor hops, and makes the
design intent explicit.

### Why not keep the NSLock?

The `NSLock` was correct and simple but redundant once the `AsyncStream` exists. With
the stream, attribute and debug mutations are commands processed in FIFO order alongside
regular RUM commands. This eliminates the lock entirely and gives a single, consistent
synchronization mechanism. The scope tree's `process()` remains synchronous — the async
boundary is at the Monitor level only.

---

## Benefits

- Features can use **actors** for state management instead of `DispatchQueue` + `@unchecked Sendable`.
- **`DatadogCore` subsystems are already actors** (`MessageBus`, `FilesOrchestrator`,
  `DataUploadWorker`). Full `DatadogCore` actor conversion is optional — the coordinator
  pattern may be preferable.
- Aligns with **Swift 6 structured concurrency** across the entire SDK.
- Eliminates the `FeatureMessageReceiver` synchronous protocol constraint that blocks actor adoption.

## Risks

- **Ordering guarantees** — the actor bus dispatches to all receivers sequentially within a
  single `send()` call, preserving cross-feature ordering per message. However, since callers
  use `Task { await bus.send() }`, the order in which messages enter the actor depends on
  Task scheduling. Per-caller ordering is preserved (FIFO within a serial caller), but
  messages from concurrent callers may interleave.
- **Test migration** — ✅ completed. All message-based test call sites updated to the new
  `receive(message:)` signature. Tests that asserted `Bool` return values were updated
  (assertions removed or changed to verify side effects instead).
- **Performance** — actor hop overhead replaces `DispatchQueue.async` overhead. Benchmark
  message throughput before and after.
