# Message Bus

The SDK's typed publish/subscribe channel for inter-feature communication. Features registered to the same core can exchange strongly-typed values without importing each other.

## Core Protocols

| Protocol | Role |
|----------|------|
| `BusMessage` | A value type (struct or enum) carried on the bus. Declares a stable `key`. |
| `BusMessageReceiver` | A class-bound receiver for one `BusMessage` type. Subscribed by identity. |
| `MessageBus` | The channel. Subscribe, unsubscribe, send. |
| `MessageBusSubscription` | Opaque handle returned by the closure-based `subscribe(block:)` API. |

All types live in `DatadogInternal/Sources/MessageBus/MessageBus.swift`. The concrete implementation is `CoreMessageBus` in `DatadogCore/Sources/Core/CoreMessageBus.swift`.

## Subscription Patterns

### Receiver-based (long-lived objects)

Implement `BusMessageReceiver` when the subscriber already has a natural lifecycle (a `Feature`, an instrumentation component). The bus retains the receiver until `unsubscribe` is called.

```swift
final class MyReceiver: BusMessageReceiver {
    typealias Message = RUMSessionState

    func receive(message: RUMSessionState, from core: DatadogCoreProtocol) {
        // handle on the bus's serial queue — do not block
    }
}

let receiver = MyReceiver()
core.messageBus.subscribe(receiver: receiver)
// ...
core.messageBus.unsubscribe(receiver: receiver)
```

Subscribe at feature enable time, typically in the module's `enable(with:in:)` function:

```swift
// DatadogRUM/Sources/RUM.swift
core.messageBus.subscribe(receiver: rum.crashReportReceiver)
core.messageBus.subscribe(receiver: rum.telemetryReceiver)
```

### Closure-based (ad-hoc subscriptions)

Use `subscribe(block:)` when no natural receiver object exists. The returned `MessageBusSubscription` owns the subscription — store it for the lifetime you need, then pass it to `unsubscribe(_:)`.

```swift
var subscriptions: [MessageBusSubscription] = []

subscriptions += [
    bus.subscribe { [weak self] (message: RUMViewEvent, _) in
        self?.update(viewEvent: message)
    },
    bus.subscribe { [weak self] (_: RUMViewReset, _) in
        self?.clearViewEvent()
    },
]

// cancel all at teardown
subscriptions.forEach { bus.unsubscribe($0) }
```

`CrashContextCoreProvider` uses this pattern to subscribe to multiple message types on one bus, retaining all handles in a `[MessageBusSubscription]` array. See `DatadogCrashReporting/Sources/CrashContextProvider.swift`.

## Sending Messages

```swift
// Fire-and-forget — no fallback needed
core.messageBus.send(message: RUMViewReset())

// With a fallback when no subscriber is registered
core.messageBus.send(message: WebViewLogMessage(event: event), else: {
    DD.logger.warn("A WebView log is lost because Logging is disabled in the SDK")
})
```

`send` is asynchronous — it dispatches on the bus's serial queue. Do not assume the message is delivered by the time `send` returns.

## Supported Messages

The table below lists every `BusMessage` type registered across the SDK.

| Type | Key | Sent by | Consumed by |
|------|-----|---------|-------------|
| `DatadogContext` | `"core.context"` | `DatadogCore` (on every context update) | `ContextSharingTransformer`, `NetworkContextCoreProvider`, `WatchdogTerminationMonitor`, `RUMContextReceiver` (SR), `ContextMessageReceiver` (Trace), `CrashContextCoreProvider` |
| `TelemetryMessage` | `"telemetry"` | Any feature via `core.telemetry.*` | `TelemetryReceiver` (RUM) |
| `LogMessage` | `"log-message"` | `TracingWithLoggingIntegration` (Trace) | `LogMessageReceiver` (Logs) |
| `LogEventAttributes` | `"log-event-attributes"` | `Logs.enable` (shared global attributes) | `CrashContextCoreProvider` |
| `Crash` | `"crash-report"` | `CrashReportSender` (CrashReporting) | `CrashReportReceiver` (RUM) |
| `RUMViewEvent` | `"rum-view-event"` | `FatalErrorContextNotifier` (RUM) | `CrashContextCoreProvider` |
| `RUMEventAttributes` | `"rum-event-attributes"` | `FatalErrorContextNotifier` (RUM) | `CrashContextCoreProvider` |
| `RUMViewReset` | `"rum-view-reset"` | `FatalErrorContextNotifier` (RUM) | `CrashContextCoreProvider` |
| `RUMSessionState` | `"rum-session-state"` | `FatalErrorContextNotifier` (RUM) | `CrashContextCoreProvider` |
| `RUMErrorMessage` | `"rum-error"` | `RemoteLogger` (Logs) | `ErrorMessageReceiver` (RUM) |
| `RUMFlagEvaluationMessage` | `"rum-flag-evaluation"` | `RUMFlagEvaluationReporter` (Flags) | `FlagEvaluationReceiver` (RUM) |
| `WebViewLogMessage` | `"webview-log"` | `MessageEmitter` (WebViewTracking) | `WebViewLogReceiver` (Logs) |
| `WebViewRUMMessage` | `"webview-rum"` | `MessageEmitter` (WebViewTracking) | `WebViewEventReceiver` (RUM) |
| `WebViewRecordMessage` | `"webview-record"` | `MessageEmitter` (WebViewTracking) | `WebViewRecordReceiver` (SR) |

### `TelemetryMessage` — special dispatch

`TelemetryMessage.configuration(...)` is intercepted by `CoreMessageBus` and **not** delivered immediately. The bus accumulates configuration updates and dispatches a single merged `TelemetryMessage.configuration` to subscribers 5 seconds after initialization. All other `TelemetryMessage` variants (`.debug`, `.error`, `.metric`, `.usage`) are delivered normally.

## How to Add a New Message

### 1. Define the message type in `DatadogInternal`

Messages live in `DatadogInternal/Sources/Models/` alongside the domain they belong to. Prefer immutable value types.

```swift
// DatadogInternal/Sources/Models/MyFeature/MyMessage.swift
public struct MyMessage: BusMessage {
    public static let key = "my-feature.my-message"  // globally unique, namespaced

    public let value: String

    public init(value: String) {
        self.value = value
    }
}
```

Rules for `key`:
- Must be **globally unique** across the SDK — check the table above before choosing.
- Use `"<module>.<purpose>"` format (e.g. `"rum-session-state"`, `"webview-log"`).
- Treat it as **immutable** after the first release — downstream tooling and crash-context serialization may depend on it.

Add the new file to the `DatadogInternal` Xcode target via the `xcode-file-management` skill.

### 2. Implement a receiver in the consuming feature

```swift
// DatadogMyFeature/Sources/Feature/MyMessageReceiver.swift
internal final class MyMessageReceiver: BusMessageReceiver {
    func receive(message: MyMessage, from core: DatadogCoreProtocol) {
        // called on the bus's serial queue — do not block
    }
}
```

### 3. Subscribe at feature enable time

```swift
// DatadogMyFeature/Sources/MyFeature.swift
core.messageBus.subscribe(receiver: feature.myMessageReceiver)
```

If you need multiple subscriptions from a single object without a natural `BusMessageReceiver` conformance, use the closure-based API and retain the handles (see `CrashContextCoreProvider` for the canonical pattern).

### 4. Send the message from the producing feature

```swift
core.messageBus.send(message: MyMessage(value: "hello"), else: {
    // invoked if no subscriber is registered
})
```

### 5. Write tests

- Subscribe to `PassthroughCoreMock.messageBus` in unit tests.
- Use `core.messageBus.send(message:)` to drive receivers in isolation.
- Assert side effects via the receiver's internal state or the core mock's recorded events.

See `DatadogInternal/Tests/MessageBus/MessageBusTests.swift` for bus-level tests and `DatadogCrashReporting/Tests/CrashContextCoreProviderTests.swift` for a feature-level example.

## Threading

All delivery runs on the bus's internal serial queue (`com.datadoghq.ios-sdk-message-bus`, QoS `.utility`). Receivers must not block — doing so delays every other subscriber. Move work off the queue immediately if it requires significant computation.

`send` and `subscribe`/`unsubscribe` are safe to call from any thread.

## Subscription Lifetime and Retain Semantics

- `subscribe(receiver:)` — the bus **strongly retains** `receiver`. Call `unsubscribe(receiver:)` at teardown, or the receiver (and anything it captures) will leak.
- `subscribe(block:)` — the bus retains the internal wrapper. The caller owns the `MessageBusSubscription`; dropping it without calling `unsubscribe(_:)` leaks the subscription.
- Features must **not** retain the `core` reference passed to `receive(message:from:)` — use it transiently within the call.
