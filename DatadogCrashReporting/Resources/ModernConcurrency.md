# Modern Concurrency Migration Guide — DatadogCrashReporting

Patterns and lessons learned from migrating `DatadogCrashReporting` to Swift 6 with `async/await`.
Use this together with the [DatadogLogs migration guide](../../DatadogLogs/Resources/ModernConcurrency.md)
as reference when applying the same migration to other feature modules.

---

## 1. Callback-returning-Bool to async + separate delete

### Before (callback returns Bool to control purging)
```swift
public protocol CrashReportingPlugin: AnyObject {
    func readPendingCrashReport(completion: @escaping (DDCrashReport?) -> Bool)
    func inject(context: Data)
    var backtraceReporter: BacktraceReporting? { get }
}
```

### After (async return + explicit delete method)
```swift
public protocol CrashReportingPlugin: AnyObject, Sendable {
    func readPendingCrashReport() async -> DDCrashReport?
    func deletePendingCrashReports()
    func inject(context: Data)
    var backtraceReporter: BacktraceReporting? { get }
}
```

**Key decisions:**
- The `Bool` return from the callback was a "should purge?" signal. With async, this
  is replaced by a separate `deletePendingCrashReports()` method — cleaner separation
  of concerns (read vs. delete).
- The caller decides when to delete, making the control flow explicit and linear.
- The protocol gains `Sendable` because implementations are stored in an actor and
  shared across isolation boundaries (e.g., accessed in `CrashReporting.enableOrThrow`
  after being passed to the coordinator).

---

## 2. Bridging KSCrash's callback API to async with `withCheckedContinuation`

KSCrash's `CrashReportStore.sendAllReports` is callback-based. Bridge it using
`withCheckedContinuation`:

```swift
func readPendingCrashReport() async -> DDCrashReport? {
    await withCheckedContinuation { continuation in
        self.store.sendAllReports { [weak self] reports, error in
            do {
                if let error { throw error }
                guard let report = reports?.first,
                      let ddReport = report.untypedValue as? DDCrashReport else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ddReport)
            } catch {
                continuation.resume(returning: nil)
                self?.store.deleteAllReports()
                self?.telemetry.error("[KSCrash] Fails to load crash report", error: error)
            }
        }
    }
}
```

**Rule:** Each path through the callback must call `continuation.resume` exactly once.
Use `do/catch` to ensure error paths also resume the continuation.

---

## 3. Actor for coordination, plain class for feature registration

### Problem
`CrashReportingFeature` conforms to `DatadogFeature` and needs to:
- Register with the core (synchronous)
- Set up a `@Sendable` callback for crash context changes
- Launch async work (sending crash reports)

If the feature itself were `Sendable`, every type it touches would need `Sendable`
conformance — a cascade of `@unchecked Sendable` annotations.

### Solution: Extract a coordinator actor

```swift
internal final class CrashReportingFeature: DatadogFeature {
    private let coordinator: CrashReportCoordinator
    // ... no Sendable needed
}

internal actor CrashReportCoordinator {
    func inject(currentCrashContext: CrashContext) { ... }
    nonisolated func sendCrashReportIfFound() -> Task<Void, Never> { ... }
}
```

**Key design decisions:**
- `CrashReportingFeature` is a lightweight wrapper — it wires things together for the
  `DatadogFeature` protocol but doesn't cross any `@Sendable` boundaries itself.
- `CrashReportCoordinator` is an actor — the compiler guarantees its thread safety.
  No `DispatchQueue`, no `@unchecked Sendable`.
- The `onCrashContextChange` callback captures `[weak coordinator]` (an actor is
  automatically `Sendable`), not `[weak self]`.
- `sendCrashReportIfFound()` is `nonisolated` — it just creates a Task and returns it.
  The Task internally `await`s the actor-isolated `performSendCrashReportIfFound()`.
- Initial context injection in `init` also wraps in a `Task` since you can't call
  actor-isolated methods from a synchronous initializer.

**When to use this pattern:**
- The feature type has synchronous protocol requirements (like `DatadogFeature`)
- The actual work (encoding, decoding, sending) can be done asynchronously
- You want to avoid cascading `Sendable` requirements across the module

---

## 4. Keeping DispatchQueue for sync protocol requirements

`CrashContextCoreProvider` implements `FeatureMessageReceiver.receive(message:)`
which is a **synchronous protocol requirement**. This prevents converting the class to
an actor. (The `from core:` parameter and `Bool` return have been removed from the
protocol, but the method itself remains synchronous.)

**Decision: Keep DispatchQueue, add `@unchecked Sendable`:**
```swift
internal class CrashContextCoreProvider: CrashContextProvider, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.datadoghq.crash-context", ...)
    // ... all mutable state synchronized via queue
}
```

**When the DispatchQueue stays vs. when to convert:**

| Keep DispatchQueue | Convert to actor |
|--------------------|------------------|
| Protocol requires sync methods (`receive`) | All callers are `async` |
| Callers need synchronous snapshots | No sync protocol constraints |
| Type is already `@unchecked Sendable` via queue | State transitions benefit from compiler isolation |

**Future:** `FeatureMessageReceiver` has been simplified (no `core:` param, no `Bool`
return), but `receive(message:)` is still synchronous. When it becomes `async`,
`CrashContextCoreProvider` can become an actor. See `DatadogInternal/Resources/TODO.md`.

---

## 5. NSObject subclasses and `@unchecked Sendable`

KSCrash integration types inherit from `NSObject` and conform to KSCrash's
`CrashReportFilter` protocol. Actors can't inherit from `NSObject`, so these stay
as classes with `@unchecked Sendable` when needed:

```swift
@objc
internal class KSCrashPlugin: NSObject, CrashReportingPlugin, @unchecked Sendable { ... }
```

**Safety invariant:** These types are immutable after initialization (`let` properties
only), so `@unchecked Sendable` is safe.

**Note:** The KSCrash filter classes (`DatadogCrashReportFilter`, `DatadogTypeSafeFilter`,
`DatadogMinifyFilter`, `DatadogDiagnosticFilter`, `AnyCrashReport`) do NOT need
`@unchecked Sendable` — they are created and consumed locally within `KSCrashPlugin`
and never cross isolation boundaries.

---

## 6. `@Sendable` closures — when forced by DispatchQueue

The `@Sendable` on `CrashContextProvider.onCrashContextChange` is forced by
`CrashContextCoreProvider`'s setter implementation:

```swift
var onCrashContextChange: @Sendable (CrashContext) -> Void {
    get { queue.sync { self._callback } }
    set { queue.async { self._callback = newValue } }  // queue.async requires @Sendable closure
}
```

The setter uses `queue.async { self._callback = newValue }`. `DispatchQueue.async`
takes a `@Sendable` closure, which captures `newValue`. For `newValue` to be captured
in a `@Sendable` closure, it must itself be `Sendable` — so the callback type must
be `@Sendable (CrashContext) -> Void`.

**Note:** The `CrashContextProvider` protocol itself does NOT need `Sendable` — the
provider never crosses isolation boundaries. Only the `onCrashContextChange` callback
needs `@Sendable`, driven by the implementation's `queue.async`.

---

## 7. Minimizing `Sendable` requirements

Not every protocol or type needs `Sendable`. Apply it only where the compiler forces
it — i.e., where a value actually crosses an isolation boundary:

| Type/Protocol | Needs `Sendable`? | Why |
|---------------|-------------------|-----|
| `CrashReportingPlugin` | Yes (`Sendable`) | Stored in actor, also accessed after being passed to feature |
| `CrashReportSender` | Yes (`Sendable`) | Crosses actor boundary — protocol type must be `Sendable` for compiler to accept it |
| `CrashContextProvider` | No | Stored in `CrashReportingFeature` (non-Sendable), never sent to actor |
| `CrashContextCoreProvider` | Yes (`@unchecked`) | Captures `self` in `queue.async` closures |
| `KSCrashPlugin` | Yes (`@unchecked`) | Conforms to `CrashReportingPlugin: Sendable` |
| `KSCrashBacktrace` | Yes (`@unchecked`) | Conforms to `BacktraceReporting: Sendable`; holds non-Sendable `Telemetry` |
| `MessageBusSender` | Yes (`@unchecked`) | Conforms to `CrashReportSender: Sendable`; struct with `weak var`, safe to share |
| KSCrash filter classes | No | Created and consumed locally, never cross boundaries |

---

## 8. DatadogInternal Sendable additions for CrashReporting

These types in DatadogInternal needed `Sendable` conformance (DatadogInternal compiles
in Swift 5 mode, so this is a no-op there but enables Swift 6 consumers):

| Type | Strategy | Rationale |
|------|----------|-----------|
| `CrashContext` | `@unchecked Sendable` | Struct with `var` properties and existential types |
| `DDCrashReport` | `@unchecked Sendable` | Struct with `AnyCodable` (`Any` wrapper) |
| `DDThread` | `Sendable` | Struct with `String`/`Bool` properties |
| `BinaryImage` | `Sendable` | Struct with `String`/`Bool` properties |
| `Crash` | `@unchecked Sendable` | Contains `DDCrashReport` + `CrashContext` |
| `LaunchReport` | `Sendable` | Struct with `let Bool` |
| `AnyCodable` | `@unchecked Sendable` | `@frozen` struct with `let value: Any` |

---

## 9. Test migration patterns

### Async task-based tests (for crash report sending)
```swift
func testItSendsCrashReport() async throws {
    await feature.sendCrashReportIfFound().value
    XCTAssertNotNil(sender.sentCrashReport)
}
```

### Expectation-based tests (for actor-isolated inject via Task)
When the path goes through a `Task` wrapping an actor call (like context injection),
use the mock's callback with `XCTestExpectation`:

```swift
func testItInjectsCrashContext() {
    let expectation = self.expectation(description: "plugin received context")
    plugin.didInjectContext = { expectation.fulfill() }

    let feature = CrashReportingFeature.mockWith(...)

    withExtendedLifetime(feature) {
        waitForExpectations(timeout: 0.5)
        XCTAssertNotNil(plugin.injectedContextData)
    }
}
```

**Why:** The inject path is: `onCrashContextChange` callback → `Task` → actor's
`inject()`. There's no returned `Task` to `await`, so expectations on the mock
callback are the synchronization mechanism.

---

## 10. Checklist for migrating another feature module

1. **Identify callback-based protocols** → convert to `async -> T?` or split into
   async read + explicit action (like read + delete)
2. **Extract an actor coordinator** for work that crosses concurrency boundaries,
   keeping the `DatadogFeature` wrapper non-Sendable
3. **Mark protocols `Sendable` only when needed** — only when instances are shared
   across isolation boundaries
4. **Bridge third-party callback APIs** using `withCheckedContinuation`
5. **Use `nonisolated` on actor methods** that just create Tasks (fire-and-forget entry points)
6. **Keep DispatchQueue** when protocols require sync methods (`receive`, `flush`)
7. **Add `@unchecked Sendable`** to classes synchronized via queues/locks
8. **Add `@unchecked Sendable`** to NSObject subclasses that are immutable after init
9. **Add `@Sendable` to closures** only when forced by `DispatchQueue.async` or actor isolation
10. **Convert tests** — use `await Task.value` for returned tasks, expectations for fire-and-forget actor calls
11. **Update mock types** to match new async signatures
12. **Update api-surface-swift** to reflect new protocol signatures
