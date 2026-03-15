# DatadogLogs — Swift 6 Migration Status

Current state of the Swift 6 / modern concurrency migration for the `DatadogLogs` module.
Use this to pick up remaining work or as a reference when migrating other modules.

---

## Completed

### async/await conversions
- `LogEventMapper` protocol — callback removed, now `func map(event:) async -> LogEvent?`
- `LogEventBuilder.createLogEvent(...)` — returns `async -> LogEvent?`
- `InternalLoggerProtocol.critical(...)` — `completionHandler` removed, now `async`
- `RemoteLogger` — uses `prepareLogContext()` + `writeLog()` async pattern
- `MessageReceivers` — `LogMessageReceiver` and `WebViewLogReceiver` now inject
  `FeatureScope` at init. `receive(message:)` simplified (no `core:` param, no `Bool`
  return). Uses `Task` inside `receive` with `await featureScope.eventWriteContext()`

### Sendable conformances
- `LogEventMapper: Sendable` (protocol)
- `RemoteLogger.Configuration: Sendable` (explicit, no `@unchecked`)
- `SyncLogEventMapper` — holds `@Sendable` closure, implicitly Sendable
- `Logs.Configuration.EventMapper` — typealias is `@Sendable (LogEvent) -> LogEvent?`
- `SynchronizedAttributes: Sendable` (via `ReadWriteLock`)
- `SynchronizedTags: Sendable` (via `ReadWriteLock`)

### DatadogInternal types made Sendable (for DatadogLogs consumption)
- `DatadogContext: @unchecked Sendable`
- `Writer: Sendable` (protocol)
- `DDError` — already Sendable (struct with String lets)
- `LogMessage: Sendable`
- `AnyEncodable: @unchecked Sendable`
- `CompletionHandler = @Sendable () -> Void`
- `AttributeValue = Encodable & Sendable`

### Patterns established
- **Prepare/Write pattern** — `prepareLogContext()` captures user-thread state synchronously,
  `writeLog()` runs async in a `Task`
- **`withCheckedContinuation`** — bridges `eventWriteContext` to async in `RemoteLogger.writeLog()`
- **Obj-C bridge** — `_internal_sync_critical` converts `[String: Any]` → `.dd.swiftAttributes`
  and `Error?` → `NSError?` before `Task`, uses `DispatchSemaphore` for sync blocking
- **ReadWriteLock kept** for `SynchronizedAttributes`/`SynchronizedTags` — actors would break
  synchronous snapshot semantics needed on the user thread

### Tests migrated
- `LogEventBuilderTests` — all 6 tests converted to `async throws`
- `LoggerTests.testWhenCriticalLoggedFromInternal_itCompletes` — async
- `ConsoleLoggerTests.testItPrintsCritical_andCompletes` — async
- `RemoteLoggerTests.testWhenCriticalLoggedFromInternal_itCallCompletion` — async
- `LogsTests` — `LogEventMapperMock` updated to async protocol

---

## Remaining — explicit Sendable annotations

These types are effectively Sendable (all stored properties are Sendable) but lack
explicit conformance. In Swift 6 mode, non-public types get implicit Sendable within
the module, but explicit annotation is better for documentation and cross-module use.

### High priority — crossed across Task boundaries

| Type | File | Why |
|------|------|-----|
| `PreparedLogContext` | `RemoteLogger.swift` | Passed into `Task { await writeLog(prepared) }` |
| `LogEventBuilder` | `LogEventBuilder.swift` | Created in `eventWriteContext`, used in `Task` in `MessageReceivers.swift` |

### Medium priority — internal types

| Type | File | Notes |
|------|------|-------|
| `LogEventSanitizer` | `LogEventSanitizer.swift` | Stateless struct |
| `LogEventEncoder` | `LogEventEncoder.swift` | Stateless struct |
| `Logs.Configuration` | `Logs.swift` | Public type, has `@Sendable` EventMapper |
| `Logger.Configuration` | `Logger.swift` | Public type |
| `ConsoleLogger` | `ConsoleLogger.swift` | + its nested `Configuration` |
| `NOPLogger` | `LoggerProtocol.swift` | Empty struct |
| `CombinedLogger` | `LoggerProtocol.swift` | Holds `[LoggerProtocol]` |
| `NOPInternalLogger` | `LoggerProtocol+Internal.swift` | Empty struct |

### Blocked on DatadogInternal

These types conform to protocols in `DatadogInternal`. Adding `Sendable` to them
requires the protocols to be `Sendable` first (which is a `DatadogInternal` change):

| Type | File | Depends on |
|------|------|------------|
| `RequestBuilder` | `RequestBuilder.swift` | `FeatureRequestBuilder: Sendable` |
| `LogsFeature` | `LogsFeature.swift` | `DatadogFeature: Sendable` (verify) |

> **Note:** `LogMessageReceiver` and `WebViewLogReceiver` are no longer blocked —
> the `FeatureMessageReceiver` protocol has been simplified to
> `func receive(message: FeatureMessage)` (no `core:` param, no `Bool` return).
> Both receivers now inject `FeatureScope` at construction time instead of
> receiving `core` in the `receive` call.

---

## Not changing

| Item | Reason |
|------|--------|
| `SynchronizedAttributes` / `SynchronizedTags` using `ReadWriteLock` | Actors would break synchronous snapshot semantics; `ReadWriteLock` allows concurrent reads |
| `DispatchSemaphore` in `_internal_sync_critical` | Required for Obj-C sync API — blocks until async write completes |
| `ReadWriteLock` implementation in `DatadogInternal` | Out of scope; `Mutex` (iOS 18+) is a future option |

---

## Reference

- `ModernConcurrency.md` (same folder) — patterns and lessons learned, reusable for other modules
- `Package.swift` — `DatadogLogs` uses `.swiftLanguageMode(.v6)`, `DatadogInternal` also uses `.swiftLanguageMode(.v6)`
