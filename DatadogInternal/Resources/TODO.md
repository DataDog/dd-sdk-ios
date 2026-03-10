# MessageBus Concurrency Migration Plan

## Context

The `MessageBus` was originally a `final class` using a `DispatchQueue` for
thread safety. The `FeatureMessageReceiver` protocol uses a synchronous callback:

```swift
public protocol FeatureMessageReceiver {
    @discardableResult
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool
}
```

This design forces features to use `DispatchQueue` + `@unchecked Sendable`
instead of Swift actors for state management.

## Current State

The `MessageBus` is now a Swift **actor**. The actor's isolation replaces the
`DispatchQueue` — receivers are dispatched synchronously within the actor.
Callers in `DatadogCore` wrap calls in `Task { await ... }` (same fire-and-forget
semantics as the old `queue.async`).

```swift
internal actor MessageBus {
    private var receivers: [String: FeatureMessageReceiver] = [:]

    func send(message: FeatureMessage, else fallback: @escaping @Sendable () -> Void = {}) {
        guard let core else { return }
        let handled = receivers.values.filter {
            $0.receive(message: message, from: core)
        }
        if handled.isEmpty { fallback() }
    }
}
```

## Open Design Decisions

### 1. Bool Return / Acknowledgment Pattern

**Current:** `receive(message:from:) -> Bool` lets `CombinedFeatureMessageReceiver`
short-circuit on the first consumer, and `send(message:else:)` fires the fallback
when no one handles a message.

**Recommendation:** Drop the "first consumer wins" pattern. All receivers get
all messages and silently ignore irrelevant ones. The `Bool` return is mostly
used for the warning log in crash reporting and can be replaced with explicit
feature-availability checks at registration time.

### 2. Core Reference (RUM-3717)

**Current:** `receive(message:from:)` passes the core on every call.

**Proposed:** Features receive the core reference once at registration time
(or via `FeatureScope`), not on every message. This aligns with:
> `// TODO: RUM-3717 — Remove core: parameter from this API once all features are migrated to depend on FeatureScope interface`

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

These compose multiple receivers and rely on the `Bool` short-circuit pattern:
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

### Phase 4: Cleanup

1. Remove `FeatureMessageReceiver` protocol.
2. Remove `CombinedFeatureMessageReceiver`.
3. Remove `core:` parameter from message handling (RUM-3717).

## Phase 5: Transform `DatadogCoreProtocol` to Enable `DatadogCore` as an Actor

Currently `DatadogCore` cannot be an actor because `DatadogCoreProtocol` defines an
entirely synchronous API surface. Every method — `register(feature:)`,
`feature(named:type:)`, `scope(for:)`, `send(message:)`, `set(context:)` — is
synchronous and called without `await` from every feature module and from the public
SDK API (`Datadog.setUserInfo`, `Datadog.set(trackingConsent:)`, etc.).

Making `DatadogCore` an actor requires transforming `DatadogCoreProtocol`:

1. **Add async overloads** to `DatadogCoreProtocol` for methods that mutate state
   (`register`, `send`, `set(context:)`, `set(anonymousId:)`).
2. **Make `FeatureScope` async** — `eventWriteContext` is a synchronous callback
   (`@escaping (DatadogContext, Writer) -> Void`). This must become an async API
   (e.g. returning `(DatadogContext, Writer)` via `async`). This cascades into every
   feature module's event recording path.
3. **Replace `flush()` with async draining** — `flush()` relies on `queue.sync {}`
   to block the caller. Actors don't support synchronous blocking. An async
   `flush() async` or a `withCheckedContinuation`-based approach is needed. Tests
   must migrate to `async` test methods.
4. **Evaluate the public API** — Customer-facing methods like `Datadog.setUserInfo()`
   are synchronous. Options:
   - Keep public API synchronous and use `Task { await core.setUserInfo(...) }` internally.
   - Provide async alternatives alongside sync ones (additive, non-breaking).
5. **Evaluate the queue architecture** — `DatadogCore` currently uses multiple
   independent queues (`readWriteQueue`, context queue, bus queue, per-feature upload
   queues) to allow parallelism between I/O and context reads. A single actor would
   serialize all access. Consider whether `DatadogCore` should be one actor or whether
   subsystems (storage, context, bus) should each be their own actor.

**Prerequisite:** Phases 3–4 above should be completed first, as they remove the
synchronous `FeatureMessageReceiver` constraint.

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

## Phase 7: Further Cleanup

1. Make `Writer` protocol async (cascades into `FeatureScope.eventWriteContext`
   and all feature modules — 25+ call sites).
2. Evaluate removing `readWriteQueue` from `DatadogCore` entirely
   (still used for `FeatureDataStore` and directory management in `FeatureStorage`).

---

## Benefits

- Features can use **actors** for state management instead of `DispatchQueue` + `@unchecked Sendable`.
- **`DatadogCore` can become an actor**, replacing `@unchecked Sendable` + `ReadWriteLock`
  with compiler-enforced isolation.
- Aligns with **Swift 6 structured concurrency** across the entire SDK.
- Eliminates the `FeatureMessageReceiver` synchronous protocol constraint that blocks actor adoption.

## Risks

- **Ordering guarantees** — the actor bus dispatches to all receivers sequentially within a
  single `send()` call, preserving cross-feature ordering per message. However, since callers
  use `Task { await bus.send() }`, the order in which messages enter the actor depends on
  Task scheduling. Per-caller ordering is preserved (FIFO within a serial caller), but
  messages from concurrent callers may interleave.
- **Test migration** is significant — all message-based tests need async adaptation.
- **Performance** — actor hop overhead replaces `DispatchQueue.async` overhead. Benchmark
  message throughput before and after.
