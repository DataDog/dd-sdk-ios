# DatadogInternal – Modern Concurrency Migration

This document tracks the decisions, patterns, and learnings from migrating
DatadogInternal to Swift 6 strict concurrency.

## Overview

DatadogInternal previously compiled in **Swift 5 mode** while feature modules
migrated to Swift 6. That meant `Sendable` conformances were declared here
but never enforced by the compiler. Moving DatadogInternal to
`.swiftLanguageMode(.v6)` made every `Sendable` declaration fully checked,
surfacing dozens of errors across context types, generated models, global
state, and Obj-C bridges.

The minimum deployment target was also raised from iOS 12 to iOS 13 to enable
`Combine` and other concurrency-related frameworks.

---

## 1. Nested enums and structs inside `Sendable` types need explicit conformance

When a struct is `Sendable`, **every stored property** must also be `Sendable`.
In Swift 5 mode the compiler didn't enforce this, so nested enums and structs
inside `Sendable` types compiled without issue. In Swift 6 each one must
explicitly conform.

| Parent struct | Nested type | Fix |
|---------------|-------------|-----|
| `LaunchInfo` | `LaunchReason` (enum) | Added `Sendable` |
| `LaunchInfo` | `LaunchPhase` (enum) | Added `Sendable` |
| `LaunchInfo` | `LaunchInfo.Raw` (struct) | Added `Sendable` |
| `BatteryStatus` | `BatteryStatus.State` (enum) | Added `Sendable` |
| `NetworkConnectionInfo` | `Reachability` (enum) | Added `Sendable` |
| `NetworkConnectionInfo` | `Interface` (enum) | Added `Sendable` |
| `ResourceMetrics` | `DateInterval` (struct) | Added `Sendable` |
| `DDCrashReport` | `Meta` (struct) | Added `Sendable` |
| `CrashContext` | `RUMSessionState` (struct) | Added `Sendable` |

All of these are pure value types with `let`-only (or primitive) properties,
so `Sendable` is safe and trivially correct.

---

## 2. `@unchecked Sendable` for types with non-Sendable existentials

Some types contain existential properties (`Any`, `Encodable`, protocol types)
that cannot conform to `Sendable`. When the type is a value type and the
existential is immutable after creation, `@unchecked Sendable` is safe.

| Type | Non-Sendable property | Safety invariant |
|------|-----------------------|------------------|
| `AnyCodable` | `value: Any` | `@frozen` struct with `let value`; immutable after init |
| `LogEventAttributes` | `attributes: [String: Encodable]` | Value type (struct); copies are independent |
| `RUMEventAttributes` | `contextInfo: [String: Encodable]` | Generated model; value type with copy semantics |
| `CoreTelemetry` | `weak var core: DatadogCoreProtocol?` | Struct with a single weak reference; set once at init |

---

## 3. Generated RUM models — `@unchecked Sendable`

`RUMViewEvent` and `Device` (in `RUMDataModels.swift`) already declared
`Sendable` conformance in Swift 5 mode. In Swift 6, the compiler verifies
that **all** nested types (enums, sub-structs) are also `Sendable`. Since the
file is generated from JSON Schema and contains hundreds of nested types,
adding `Sendable` to each one is impractical.

**Fix:** Changed `Sendable` → `@unchecked Sendable` on `RUMViewEvent` and
`Device`. All nested types are pure value types (structs with `let` properties,
enums with `String` raw values), so the invariant holds.

---

## 4. `@ReadWriteLock` property wrapper + static vars

Swift 6 flags `static var` properties as `nonisolated global shared mutable
state`, regardless of whether a property wrapper provides thread safety.
`nonisolated(unsafe)` **cannot** be combined with property wrappers.

**Fix:** Replace the `@ReadWriteLock` property wrapper syntax with a manual
`static let` holding the `ReadWriteLock` instance (which is `@unchecked
Sendable`) and a computed `static var` forwarding to its `wrappedValue`:

```swift
// Before — compiler error in Swift 6
@ReadWriteLock
public static var logger: CoreLogger = InternalLogger(...)

// After — static let is concurrency-safe (ReadWriteLock is @unchecked Sendable)
private static let _logger = ReadWriteLock<CoreLogger>(wrappedValue: InternalLogger(...))
public static var logger: CoreLogger {
    get { _logger.wrappedValue }
    set { _logger.wrappedValue = newValue }
}
```

Applied to:
- `DD.logger`
- `CoreRegistry.instances`

---

## 5. `nonisolated(unsafe)` for other global mutable state

For global/static mutable state that is either protected by external
synchronization or is an associated-object key (address-only, never mutated):

| Global | Rationale |
|--------|-----------|
| `Swizzling.swizzlings` | Protected by `NSLock` in `Swizzling.sync` |
| `ObjcException.rethrow` | Set once during SDK init; closure-typed static |
| `hasCompletionKey` (URLSessionTask extension) | Associated-object key; address used, never mutated |
| `consolePrint` | Already had `nonisolated(unsafe)` |

---

## 6. `static var` → `static let` where the value never changes

Protocol requirements with `{ get }` allow `static let` in conformers.
When the value is a constant, prefer `let` over `var` to satisfy Swift 6
without `nonisolated(unsafe)`.

- `BacktraceReportingFeature.name`: changed from `static var` to `static let`

---

## 7. Making Benchmark protocols `Sendable`

The `bench` global holds a tuple of `(BenchmarkProfiler, BenchmarkMeter)`.
In Swift 6 a `let` with non-Sendable type triggers a global-state error.

**Fix:** Made `BenchmarkProfiler` and `BenchmarkMeter` protocols inherit
from `Sendable`, and made `NOPBench` conform to `@unchecked Sendable`.
This is safe because `NOPBench` is stateless (all methods are no-ops).

---

## 8. `@unchecked Sendable` for Obj-C bridge types

`objc_TracingHeaderType` is a `final class` with only `let` properties.
Immutable after initialization, so `@unchecked Sendable` is safe. This
resolves the static property errors (`datadog`, `b3multi`, `b3`,
`tracecontext`).

---

## 9. Impact on other modules

DatadogInternal is imported by every feature module. These changes are
**source-compatible** for all consumers:

- Adding `Sendable` to enums and structs doesn't break existing code
- `@unchecked Sendable` is transparent to callers
- The `ReadWriteLock` refactoring preserves the same API (`DD.logger`,
  `CoreRegistry.instances`) — only the internal storage changed
- Protocol `Sendable` additions (`BenchmarkProfiler`, `BenchmarkMeter`)
  don't break Swift 5 conformers; enforcement applies when they migrate to
  Swift 6

---

## Files Modified

### Context types
- `Sources/Context/LaunchInfo.swift` — `Sendable` on `LaunchReason`, `LaunchPhase`, `LaunchInfo.Raw`
- `Sources/Context/BatteryStatus.swift` — `Sendable` on `BatteryStatus.State`
- `Sources/Context/NetworkConnectionInfo.swift` — `Sendable` on `Reachability`, `Interface`

### Codable
- `Sources/Codable/AnyCodable.swift` — `Sendable` → `@unchecked Sendable`

### Models
- `Sources/Models/CrashReporting/DDCrashReport.swift` — `Sendable` on `Meta`
- `Sources/Models/CrashReporting/CrashContext.swift` — (benefits from nested type fixes)
- `Sources/Models/RUM/RUMPayloadMessages.swift` — `Sendable` on `RUMSessionState`
- `Sources/Models/RUM/RUMDataModels.swift` — `@unchecked Sendable` on `Device`, `RUMViewEvent`, `RUMEventAttributes`
- `Sources/Models/Logs/LogEventAttributes.swift` — `@unchecked Sendable`

### Telemetry
- `Sources/Telemetry/Telemetry.swift` — `@unchecked Sendable` on `CoreTelemetry`

### Global state
- `Sources/DD.swift` — `@ReadWriteLock` → manual `ReadWriteLock` + computed property
- `Sources/CoreRegistry.swift` — same pattern
- `Sources/Swizzling/MethodSwizzler.swift` — `nonisolated(unsafe)` on `swizzlings`
- `Sources/Utils/DDError.swift` — `nonisolated(unsafe)` on `ObjcException.rethrow`
- `Sources/NetworkInstrumentation/URLSession/URLSessionTask+Tracking.swift` — `nonisolated(unsafe)` on `hasCompletionKey`

### Feature / benchmark
- `Sources/BacktraceReporting/BacktraceReportingFeature.swift` — `static var` → `static let`
- `Sources/Benchmarks/BenchmarkProfiler.swift` — `Sendable` on protocols, `@unchecked Sendable` on `NOPBench`

### Obj-C bridges
- `Sources/NetworkInstrumentation/TracingHeaderType+objc.swift` — `@unchecked Sendable` on `objc_TracingHeaderType`
