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

### Phase 2: Migrate DatadogCore

1. Update `MessageBus` to support both sync receivers and async streams.
2. Update `DatadogCore.register(feature:)` to create and vend streams.
3. Update `send(message:else:)` — yield to async streams and call sync receivers.

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

## Benefits

- Features can use **actors** for state management instead of `DispatchQueue` + `@unchecked Sendable`.
- Natural **backpressure** handling via `AsyncStream` buffering policies.
- Aligns with **Swift 6 structured concurrency** across the entire SDK.
- Eliminates the `FeatureMessageReceiver` synchronous protocol constraint that blocks actor adoption.
- Each feature processes messages in its **own isolation domain**, reducing shared-state coordination.

## Risks

- **Cross-feature ordering** is no longer deterministic — validate that no feature depends on it.
- **Test migration** is significant — all message-based tests need async adaptation.
- **Performance** — `AsyncStream` has different overhead characteristics than `DispatchQueue.async`. Benchmark message throughput before and after.
- **Backpressure** — if a feature falls behind, messages buffer. Choose an appropriate `AsyncStream.Continuation.BufferingPolicy` (`.unbounded` to match current behavior, or `.bufferingNewest(N)` with drop semantics).
