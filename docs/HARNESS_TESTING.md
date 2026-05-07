# Harness Testing

The `IntegrationUnitTests` target hosts a **harness** — a micro-framework that runs the real SDK against a simulated app environment. Tests interact only through public SDK APIs; outcomes are checked via matchers (`RUMSessionMatcher`, `LogMatcher`).

This doc is a reference for the framework. The workflow for adding a single test lives in the `dd-sdk-ios:add-harness-test` skill.

## Properties

- **Black-box.** No internal SDK state is accessed. Only public APIs and emitted events.
- **Fast.** Discrete time simulation via `DateProviderMock` — no real-time waits. The full Logs + RUM harness runs in seconds.
- **Deterministic.** Each test gets its own `AppRunner` with isolated mocks (date, app state, notifications, storage).
- **Composable.** A fluent `given()`/`when()`/`and()`/`then()` grammar lets a single setup branch into multiple `when` scenarios.

## Architecture

### File layout

```
Datadog/IntegrationUnitTests/
├── AppRunner/                    # The micro-framework
│   ├── AppRunner.swift           # SDK-agnostic core: app lifecycle, mocks, state
│   ├── AppRunner+Core.swift      # SDK init, user info, flush; computed `core`
│   ├── AppRunner+RUM.swift       # RUM enable, monitor, recordedRUMSessions, view tracking
│   ├── AppRunner+Logs.swift      # Logs enable, named loggers, recordedLogs
│   ├── AppRun.swift              # Fluent chain (given/when/and/then) + AppRunResult
│   ├── AppRunStep.swift          # Step struct + SDK-agnostic step factories (lifecycle)
│   ├── AppRunStep+Core.swift     # SDK init, user info, flushDatadogContext factories
│   ├── AppRunStep+RUM.swift      # RUM Use Cases (view, action, resource, session)
│   └── AppRunStep+Logs.swift     # enableLogs, createLogger, withLogger
├── RUM/                          # RUM harness tests
│   ├── RUMSessionTestsBase.swift # Base XCTestCase: shared time fixtures + session builders
│   ├── RUMSessionStartInForegroundTests.swift
│   └── …
├── Logs/                         # Logs harness tests
│   └── LogsBasicTests.swift
├── RUMHarness.xctestplan
└── LogsHarness.xctestplan
```

### SDK-agnostic core + per-feature extensions

`AppRunner.swift` and `AppRunStep.swift` are SDK-agnostic — they know about app lifecycle, time, mocks, and the step grammar, but nothing about Datadog products. Each SDK product gets a pair of extension files:

- `AppRunner+<Feature>.swift` — feature-specific methods on the runner (enable, monitor accessors, retrieval).
- `AppRunStep+<Feature>.swift` — static factories returning `AppRunStep` for that feature's use cases.

Per-feature *state* lives in a single anonymous slot on `AppRunner`:

```swift
// AppRunner.swift
internal class AppRunner {
    var state: [String: Any] = [:]
    // … and `tearDown()` resets it with `state.removeAll()`
}

// AppRunner+Core.swift
extension AppRunner {
    var core: DatadogCoreProxy! {
        get { state["core"] as? DatadogCoreProxy }
        set { /* set or removeValue */ }
    }
}

// AppRunner+Logs.swift
extension AppRunner {
    var loggers: [String: LoggerProtocol] {
        get { state["loggers"] as? [String: LoggerProtocol] ?? [:] }
        set { state["loggers"] = newValue }
    }
}
```

This is what makes adding a new SDK product a **drop-in** operation: create `AppRunner+Trace.swift` and `AppRunStep+Trace.swift`, add a computed property over `state["trace"]` if the feature needs storage, register tests in a new `TraceHarness.xctestplan`. `AppRunner.swift`/`AppRunStep.swift` stay untouched.

## Core Components

| Type | File | Role |
|------|------|------|
| `AppRunner` | `AppRunner.swift` | Simulates the iOS app process: process launch, app state transitions, time, mocks. Holds `state` keyed storage. |
| `AppRunStep` | `AppRunStep.swift` | Wrapper around `(AppRunner) -> Void`. Static factories live in `+Core`/`+RUM`/`+Logs` files. |
| `AppRun` | `AppRun.swift` | Fluent builder — `given(...).and(...).when(...).then()`. Hashable to allow shared `given` branches. |
| `AppRunResult` | `AppRun.swift` | Value returned by `then()`: `sessions: [RUMSessionMatcher]`, `logs: [LogMatcher]`. Empty arrays for features that weren't enabled. |
| `RUMSessionTestsBase` | `RUM/RUMSessionTestsBase.swift` | Optional `XCTestCase` base. Shared time deltas (`dt1`–`dt7`, `accuracy`) and session builders (`userSession()`, `userSessionWithManualView()`, `backgroundSession()`, …). Logs has no analogous base. |
| `RUMSessionMatcher` | `TestUtilities/Sources/Matchers/` | Groups RUM events by session ID, exposes views/actions/resources/long tasks. |
| `LogMatcher` | `TestUtilities/Sources/Matchers/` | Asserts on log status, message, service, tags, attributes. |

`then()` returns an `AppRunResult`. Use `result.sessions.takeSingle()` / `takeTwo()` for exact-count assertions; access `result.logs[i]` directly.

## Step catalog

Steps grouped by file. Each is a static factory on `AppRunStep`.

### `AppRunStep.swift` (lifecycle)

| Step | Effect |
|------|--------|
| `appLaunch(type:)` | Simulates process launch with `AppRunner.ProcessLaunchType` (user/prewarm/background, scene-delegate vs app-delegate). |
| `advanceTime(by:)` | Moves the simulated clock forward. |
| `appBecomesActive(after:)` | Advances time, transitions to `.active`. |
| `appEntersBackground(after:)` | Advances time, transitions to `.background`. |

### `AppRunStep+Core.swift`

| Step | Effect |
|------|--------|
| `initializeSDK(sdkSetup:)` | Initializes the SDK without enabling any feature. Pair with `enableRUM(rumSetup:)` and/or `enableLogs(logsSetup:)`. |
| `setUserInfo(after:id:name:email:extraInfo:)` | Sets user info on core. |
| `addUserExtraInfo(after:_:)` | Adds extra info; passing `nil` for a key clears it. |
| `clearUserInfo(after:)` | Clears all user info. |
| `flushDatadogContext()` | Synchronizes on the context provider queue. |

### `AppRunStep+RUM.swift`

| Step | Effect |
|------|--------|
| `appDisplaysFirstFrame(after:)` | Triggers the RUM frame info provider — required for TTID. |
| `enableRUM(after:sdkSetup:rumSetup:)` | Convenience: advance + initializeSDK + enableRUM in one. Do not combine with `initializeSDK` step. |
| `enableRUM(rumSetup:)` | Enables RUM only. Assumes SDK is already initialized. |
| `stopSession(after:)` | `rum.stopSession()`. |
| `timeoutSession()` | Advances time by the session timeout. |
| `startManualView(after:viewName:viewKey:)` / `stopManualView(after:viewKey:)` | Manual view tracking. |
| `startAutomaticView(after:viewController:)` / `stopAutomaticView(after:viewController:)` | UIKit auto-tracking via `viewDidAppear/Disappear` (not on watchOS). |
| `trackTwoActions(after1:after2:)` | Two custom actions. |
| `trackResource(after:duration:)` | Start + stop a resource in one step. |
| `startResource(after:key:url:)` / `stopResource(after:key:)` | Resource tracked across multiple steps. |
| `trackTwoLongTasks(after1:after2:duration1:duration2:)` | Two long tasks. |

### `AppRunStep+Logs.swift`

| Step | Effect |
|------|--------|
| `enableLogs(logsSetup:)` | Enables Logs. Assumes SDK is already initialized. |
| `createLogger(_:setup:)` | Registers a persistent named logger (default name `"default"`). |
| `withLogger(_:_:)` | Runs a closure against a named logger. The closure can call any `LoggerProtocol` API — new logger APIs do not require new step factories. |

## How to extend

### Adding a new step within an existing feature

1. Pick the right file by feature: lifecycle → `AppRunStep.swift`, core → `+Core`, RUM → `+RUM`, Logs → `+Logs`.
2. Add a static factory. Convention: name describes the action (`trackX`, `startX`, `stopX`, `appX`); first parameter is typically `after dt: TimeInterval`.

```swift
// AppRunStep+RUM.swift
static func trackError(after dt: TimeInterval, message: String) -> AppRunStep {
    return AppRunStep({ app in
        app.advanceTime(by: dt)
        app.rum.addError(message: message, type: nil, source: .source, attributes: [:])
    })
}
```

### Adding a new `AppRunner` capability within an existing feature

1. Add the method to `AppRunner+<Feature>.swift`.
2. If the capability needs storage (e.g., a registered observer, a feature-specific proxy), expose it as a computed property over `state["<key>"]`. Do **not** add a stored property on `AppRunner` — Swift extensions can't, and the anonymous-state pattern is the way per-feature state attaches.
3. If the new capability requires simulating something the runner doesn't support yet (network state, push notification, …), add the underlying mock storage to `AppRunner.swift` (storage there is SDK-agnostic) and the method to `AppRunner+<Feature>.swift`.

### Adding a new SDK product (Trace, Crash Reporting, …)

The golden path — no edits to `AppRunner.swift` or `AppRunStep.swift`:

1. **`AppRunner+<Feature>.swift`**
   - `enable<Feature>(_:)` — initialize and enable the product against `core`.
   - Computed property over `state["<feature>"]` for any per-feature storage (monitor proxy, registered handlers).
   - `recorded<Feature>Events()` — retrieval via `core.waitAndReturn…Matchers()`.
2. **`AppRunStep+<Feature>.swift`** — static factories for the product's use cases (`enable<Feature>`, plus per-action factories).
3. **`AppRunResult`** — extend `then()` only if the product has its own retrieval API; add a property (e.g., `spans: [SpanMatcher]`) and populate it in `AppRun.then()`.
4. **`<Feature>Harness.xctestplan`** — new test plan filtering to that feature's test methods.
5. **Optional base test class** (à la `RUMSessionTestsBase`) — add only if there's a recurring scenario shape worth abstracting; otherwise tests inherit from `XCTestCase` directly (Logs has no base).

## Conventions

- **Test method naming**: `testGiven<precondition>_when<action>_<and more context>()` — Given/When/Then structure.
- **Time deltas**: use the shared `dt1`–`dt7` from `RUMSessionTestsBase` for readable, consistent times. Define equivalent constants per-test if you don't inherit from it.
- **Accuracy**: use the shared `accuracy` constant for time-based assertions; pair with `DDAssertEqual(_:_:accuracy:)` (it unwraps optionals).
- **Permutation coverage**: loop over multiple `given` setups (with/without `trackBackgroundEvents`, different launch types) and multiple `when` branches to maximize scenarios from one test method.
- **Session shape comments**: document expected session shape with ASCII notation:
  ```
  /// [FG:ApplicationLaunch] → [FG:AutomaticView] → [BG:(no view)]
  ```
- **`xctestplan` registration**: each new test method must be added to the appropriate `*Harness.xctestplan`'s `selectedTests` list — the test plan whitelists by method name.

## Running

```bash
make test-ios SCHEME="TestHarness" TEST_PLAN="LogsHarness"
make test-ios SCHEME="TestHarness" TEST_PLAN="RUMHarness"
```

Both run on the `DatadogIntegrationTests` target via the `TestHarness` scheme.
