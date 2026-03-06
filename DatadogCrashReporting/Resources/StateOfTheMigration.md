# DatadogCrashReporting — Swift 6 Migration Status

Current state of the Swift 6 / modern concurrency migration for the `DatadogCrashReporting` module.
Use this to pick up remaining work or as a reference when migrating other modules.

---

## Completed

### async/await conversions
- `CrashReportingPlugin` protocol — callback-returning-Bool removed, now `func readPendingCrashReport() async -> DDCrashReport?` + separate `deletePendingCrashReports()`
- `KSCrashPlugin.readPendingCrashReport()` — bridges KSCrash's `sendAllReports` callback via `withCheckedContinuation`
- `CrashReportCoordinator.performSendCrashReportIfFound()` — fully async internal flow

### Actor extraction
- Extracted `CrashReportCoordinator` **actor** from `CrashReportingFeature`
- The coordinator owns: `plugin`, `sender`, `telemetry`, `inject()`, `performSendCrashReportIfFound()`, `encode()`, `decode()`
- `CrashReportingFeature` is a plain (non-Sendable) class — wires things for `DatadogFeature` protocol
- `sendCrashReportIfFound()` is `nonisolated` on the actor — creates a `Task` and returns it
- Initial context injection in `init` wraps in `Task { [coordinator] in await coordinator.inject(...) }`
- `onCrashContextChange` captures `[weak coordinator]` (actor is automatically Sendable)
- `Flushable` conformance removed from `CrashReportingFeature` — actor serialization replaces `DispatchQueue`

### Sendable conformances
- `CrashReportingPlugin: AnyObject, Sendable` (protocol) — stored in actor, also accessed after feature init
- `CrashReportSender: Sendable` (protocol) — crosses actor boundary when passed to coordinator
- `MessageBusSender: @unchecked Sendable` — struct with only `weak var core`, safe to share
- `CrashContextCoreProvider: @unchecked Sendable` — all mutable state synchronized via `DispatchQueue`
- `KSCrashPlugin: @unchecked Sendable` (NSObject subclass) — immutable after init, conforms to `Sendable` plugin protocol
- `KSCrashBacktrace: @unchecked Sendable` — immutable struct, holds non-Sendable `Telemetry` from DatadogInternal
- `CrashReportException: Sendable` — struct with `let String`
- `onCrashContextChange` callback typed `@Sendable (CrashContext) -> Void` — forced by `queue.async` in setter

### DatadogInternal types made Sendable (for CrashReporting consumption)
- `CrashContext: @unchecked Sendable` — struct with `var` properties and existential types
- `DDCrashReport: @unchecked Sendable` — struct with `AnyCodable` (`Any` wrapper)
- `DDThread: Sendable` — struct with String/Bool lets
- `BinaryImage: Sendable` — struct with String/Bool lets
- `Crash: @unchecked Sendable` — contains DDCrashReport + CrashContext
- `LaunchReport: Sendable` — struct with `let Bool`
- `AnyCodable: @unchecked Sendable` — `@frozen` struct with `let value: Any`

### Tests migrated
- `CrashReportingFeatureTests` — async tests use `await feature.sendCrashReportIfFound().value`
- Context injection tests use `XCTestExpectation` with `plugin.didInjectContext` callback
- `CrashReporterTests` (DatadogCore) — adapted to new async plugin API

### Mocks updated
- `CrashReportingPluginMock: @unchecked Sendable` — async `readPendingCrashReport()`, added `deletePendingCrashReports()`, callback hooks
- `NOPCrashReportingPlugin: @unchecked Sendable` — async no-op implementation
- `CrashReportSenderMock: @unchecked Sendable` — mutable test state, conforms to `Sendable` protocol
- `CrashContextProviderMock` — no `Sendable` needed (protocol doesn't require it)

### API surface
- `api-surface-swift` updated to reflect new `CrashReportingPlugin` signature

---

## Not changing

| Item | Reason |
|------|--------|
| `CrashContextCoreProvider` using `DispatchQueue` | `FeatureMessageReceiver.receive(message:from:)` is a synchronous protocol requirement — actors can't satisfy it |
| KSCrash filter classes (`DatadogCrashReportFilter`, `DatadogTypeSafeFilter`, `DatadogMinifyFilter`, `DatadogDiagnosticFilter`, `AnyCrashReport`) without `Sendable` | Created and consumed locally within `KSCrashPlugin`, never cross isolation boundaries |
| `KSCrashPlugin` as class (not actor) | Inherits from `NSObject` for KSCrash compatibility |

---

## Known future improvements

### Blocked on DatadogInternal

These improvements become possible once `DatadogInternal` migrates:

| Item | Depends on | Effect |
|------|------------|--------|
| Convert `CrashContextCoreProvider` to actor | `FeatureMessageReceiver` → `AsyncStream`-based message bus | Removes `DispatchQueue` + `@unchecked Sendable` from the provider |
| Remove `@unchecked Sendable` from `KSCrashBacktrace` | `Telemetry` protocol becoming `Sendable` | Struct would be implicitly Sendable |
| Remove `sending` on `CrashReportCoordinator.init` for `telemetry` | `Telemetry` becoming `Sendable` | Cleaner actor init |

See `DatadogInternal/Resources/TODO.md` for the AsyncStream message bus migration plan.

### Module-internal

| Item | Notes |
|------|-------|
| Explicit `Sendable` on `CrashReportingFeature` static properties | `crashContextEncoder` and `crashContextDecoder` are `static let` — implicitly safe but could be documented |
| Consider `withCheckedThrowingContinuation` in `KSCrashPlugin` | Current impl catches + resumes with `nil`, could surface errors if callers want them |

---

## File-by-file summary

| File | Concurrency status | Notes |
|------|--------------------|-------|
| `CrashReporting.swift` | Done | Entry point, synchronous — creates feature + coordinator |
| `CrashReportingFeature.swift` | Done | Plain class + `CrashReportCoordinator` actor |
| `CrashReportingPlugin.swift` | Done | `async` protocol, `Sendable` |
| `CrashReportSender.swift` | Done | `Sendable` protocol, `MessageBusSender: @unchecked Sendable` |
| `CrashContextProvider.swift` | Done (DispatchQueue kept) | `@unchecked Sendable`, blocked on sync `receive` protocol |
| `CrashReportException.swift` | Done | `Sendable` struct |
| `KSCrashPlugin.swift` | Done | `@unchecked Sendable` NSObject, `withCheckedContinuation` bridge |
| `KSCrashBacktrace.swift` | Done | `@unchecked Sendable` (non-Sendable `Telemetry`) |
| `AnyCrashReport.swift` | Done | Local to KSCrash pipeline, no Sendable needed |
| `DatadogCrashReportFilter.swift` | Done | Local filter, no Sendable needed |
| `DatadogTypeSafeFilter.swift` | Done | Local filter, no Sendable needed |
| `DatadogMinifyFilter.swift` | Done | Local filter, no Sendable needed |
| `DatadogDiagnosticFilter.swift` | Done | Local filter, no Sendable needed |
| `CrashFieldDictionary.swift` | Done | Helper, no concurrency concerns |

---

## Compilation status

**Not fully verified.** The module targets `.swiftLanguageMode(.v6)` in `Package.swift`. The last known issue was a `sending` annotation on the `CrashReportCoordinator` actor init for the `telemetry` parameter (non-Sendable `Telemetry` from DatadogInternal). The `sender` parameter resolved after making `CrashReportSender: Sendable`.

**To verify:** Build with `swift build` or Xcode — the toolchain must be Swift 6.0+ (the `Package.swift` uses Swift tools 6.2).

---

## Reference

- `ModernConcurrency.md` (same folder) — patterns and lessons learned, reusable for other modules
- `DatadogLogs/Resources/StateOfTheMigration.md` — sibling migration status for DatadogLogs
- `DatadogLogs/Resources/ModernConcurrency.md` — original migration guide from DatadogLogs
- `DatadogInternal/Resources/TODO.md` — AsyncStream message bus migration plan
- `Package.swift` — `DatadogCrashReporting` uses `.swiftLanguageMode(.v6)`, `DatadogInternal` is Swift 5
