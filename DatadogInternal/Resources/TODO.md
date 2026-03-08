# AsyncStream Message Bus — Migration Plan

## Context

The current `FeatureMessageReceiver` protocol uses a synchronous callback pattern:

```swift
public protocol FeatureMessageReceiver {
    @discardableResult
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool
}
```

The `MessageBus` dispatches messages on a serial `DispatchQueue`. Each registered feature's receiver is called synchronously within that queue, and the `Bool` return indicates whether the message was consumed.

This design forces every feature that receives messages to conform to a synchronous interface, which prevents using Swift actors for state management. Features that need thread-safe mutable state (e.g. `CrashContextCoreProvider`, RUM receivers) must use `DispatchQueue` + `@unchecked Sendable` instead of leveraging structured concurrency.

## Proposed Design

Replace the synchronous `FeatureMessageReceiver` callback with an `AsyncStream<FeatureMessage>`-based message bus, enabling features to consume messages within their own async/actor context.

### Core Side

```swift
// Each feature gets its own stream when registered
let (stream, continuation) = AsyncStream<FeatureMessage>.makeStream()
```

The `MessageBus` holds a `[String: AsyncStream<FeatureMessage>.Continuation]` map. When `send(message:)` is called, it yields the message to all active continuations.

### Feature Side

Features consume messages in their own isolation domain:

```swift
// Actor-based feature
actor MyCrashContextProvider {
    func startListening(to stream: AsyncStream<FeatureMessage>, core: DatadogCoreProtocol) {
        Task {
            for await message in stream {
                handle(message, from: core)
            }
        }
    }
}
```

## Design Decisions to Make

### 1. Bool Return / Acknowledgment Pattern

**Current behavior:** `receive(message:from:) -> Bool` lets `CombinedFeatureMessageReceiver` short-circuit on the first consumer, and the `send(message:else:)` fallback fires when no one handles a message.

**Options:**
- **Broadcast to all**: Drop the "first consumer wins" pattern. All features receive all messages and silently ignore irrelevant ones. The `else` fallback becomes a timeout or is removed.
- **Async acknowledgment**: Features return an async response through a channel. Adds complexity but preserves the feedback loop.
- **Topic-based routing**: Features subscribe to specific message types. The bus routes only relevant messages to each feature, eliminating the need for a Bool return.

**Recommendation:** Start with broadcast-to-all. The `Bool` return is mostly used for the warning log in crash reporting ("RUM feature must be enabled") and can be replaced with explicit feature-availability checks at registration time.

### 2. Ordering Guarantees

**Current behavior:** Messages are processed synchronously on one serial queue — deterministic cross-feature ordering.

**With AsyncStream:** Each feature processes messages at its own pace. Feature A might process message N+1 before Feature B finishes message N.

**Recommendation:** Per-feature ordering is preserved by `AsyncStream` (FIFO). Cross-feature ordering is rarely needed in practice — each feature handles independent concerns. Document that cross-feature ordering is not guaranteed.

### 3. Feature Lifecycle

When a feature is deregistered, its stream continuation must be finished:

```swift
func removeReceiver(forKey key: String) {
    continuations[key]?.finish()
    continuations.removeValue(forKey: key)
}
```

Features should handle stream termination gracefully (the `for await` loop exits naturally).

### 4. Core Reference

**Current:** `receive(message:from:)` passes the core on every call.

**Proposed:** Features receive the core reference once at registration time (or via `FeatureScope`), not on every message. This aligns with the existing TODO in the codebase:
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

### Phase 1: New AsyncStream MessageBus in DatadogInternal

1. Define a new `AsyncMessageBus` (or extend `MessageBus`) that manages `AsyncStream.Continuation` per feature.
2. Define a new feature protocol (e.g. `AsyncFeatureMessageReceiver` or integrate into `DatadogFeature` directly).
3. Keep the old `FeatureMessageReceiver` protocol alongside the new one for incremental migration.

### Phase 2: Convert `MessageBus` to an Actor

`MessageBus` is a strong candidate for actor conversion because:
- It is an internal class with no public API surface.
- All mutable state (`core`, `bus`, `configuration`) is already protected by a single
  serial `DispatchQueue`, which maps directly to actor isolation.
- All mutations (`connect`, `removeReceiver`, `send`, `save`) use `queue.async {}`,
  which become natural actor-isolated methods.

**`flush()` is not a real blocker.** `MessageBus.flush()` uses `queue.sync {}`, which
actors cannot do. However, `flush()` is effectively test infrastructure:
- `MessageBus.flush()` is only called from `DatadogCore.flush()`.
- `DatadogCore.flush()` is only called from `DatadogCore.flushAndTearDown()`.
- `flushAndTearDown()` is called from `Datadog.clearAllData()` (production) and tests.
- The implementation itself acknowledges this: *"this is enough to get consistency in
  tests — but won't be reliable in any public 'deinitialize' API."*

The synchronous `flush()` pattern needs replacement regardless of actor conversion.
Replace with `func drain() async` that awaits all pending work via structured
concurrency. `Datadog.clearAllData()` can bridge with `Task { await core.drain() }`.

**Steps:**
1. Convert `MessageBus` from `final class` to `actor`.
2. Remove the `DispatchQueue` — actor isolation replaces it.
3. Replace `flush()` with `func drain() async` (or remove if the `AsyncStream`
   approach from Phase 1 makes it unnecessary — finishing continuations naturally
   drains pending messages).
4. Update `DatadogCore` to `await` bus methods (or use `Task {}` from sync call sites).
5. Manage `AsyncStream.Continuation` per feature instead of holding sync receivers.
6. Update `send(message:else:)` — yield to async streams. The `else` fallback can
   become a timeout or be replaced by feature-availability checks at registration.

### Phase 3: Migrate Features (one at a time)

Migrate each module independently:
1. Replace `FeatureMessageReceiver` conformance with async stream consumption.
2. Convert `@unchecked Sendable` classes to actors where appropriate.
3. Update tests to use async patterns.

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
4. Remove sync `MessageBus` dispatch queue.

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

**Prerequisite:** The AsyncStream MessageBus migration (phases 1–4 above) should be
completed first, as it removes the synchronous `FeatureMessageReceiver` constraint.

## Phase 6: Storage Subsystem as Actor

The storage subsystem in `DatadogCore` (`FeatureStorage`, `FilesOrchestrator`,
`FileWriter`, `FileReader`, `DataReader`) shares a single `readWriteQueue` for
serializing all file I/O. All components are `@unchecked Sendable` and rely on
external queue discipline for safety.

The ideal end state is a **StorageActor** that unifies orchestration and I/O:

- `FilesOrchestrator` has unprotected mutable state (`lastWritableFileName`,
  `lastWritableFileObjectsCount`, etc.) that relies on the shared queue.
- `FileReader` has mutable `filesRead: Set<String>` also relying on the queue.
- `DataReader` is a thin wrapper that dispatches `FileReader` calls to the queue.
- `FileWriter` dispatches writes to the same queue.

Merging these into a single actor eliminates `DataReader`, the `queue` on `FileWriter`,
`@unchecked Sendable` on `FilesOrchestrator`/`FeatureStorage`, and the `@ReadWriteLock`
on `pendingBatches`.

**Blocked on:** `Writer` protocol (in `DatadogInternal`) being synchronous. Making
`Writer.write` async propagates through `FeatureScope.eventWriteContext` and into
every feature module (25+ call sites across RUM, Logs, Trace, SessionReplay,
CrashReporting, Flags, Profiling). This should be done alongside the `FeatureScope`
async migration (Phase 5 above).

---

## Benefits

- Features can use **actors** for state management instead of `DispatchQueue` + `@unchecked Sendable`.
- **`DatadogCore` can become an actor**, replacing `@unchecked Sendable` + `ReadWriteLock`
  with compiler-enforced isolation.
- Natural **backpressure** handling via `AsyncStream` buffering policies.
- Aligns with **Swift 6 structured concurrency** across the entire SDK.
- Eliminates the `FeatureMessageReceiver` synchronous protocol constraint that blocks actor adoption.
- Each feature processes messages in its **own isolation domain**, reducing shared-state coordination.

## Risks

- **Cross-feature ordering** is no longer deterministic — validate that no feature depends on it.
- **Test migration** is significant — all message-based tests need async adaptation.
- **Performance** — `AsyncStream` has different overhead characteristics than `DispatchQueue.async`. Benchmark message throughput before and after.
- **Backpressure** — if a feature falls behind, messages buffer. Choose an appropriate `AsyncStream.Continuation.BufferingPolicy` (`.unbounded` to match current behavior, or `.bufferingNewest(N)` with drop semantics).
