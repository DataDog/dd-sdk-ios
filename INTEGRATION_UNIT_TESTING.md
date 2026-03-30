# Integration Unit Testing Framework

## Overview

The `IntegrationUnitTests` target contains a **micro-framework** for black-box integration testing of the Datadog SDK. It follows the [test harness](https://en.wikipedia.org/wiki/Test_harness) model: instead of mocking SDK internals, it runs the real SDK against a simulated app environment (`AppRunner`). Tests interact exclusively through **public SDK APIs** and verify outcomes via `RUMSessionMatcher`.

Key properties:
- **Black-box**: No internal SDK state is accessed. Only public APIs and emitted RUM events are used.
- **Fast**: Uses discrete time simulation (`DateProviderMock`) — no real-time waits. 450+ tests run in ~10 seconds.
- **Deterministic**: Each test gets its own `AppRunner` with isolated mocks (date, app state, notifications, storage).
- **Composable**: A fluent `given()`/`when()`/`then()` grammar enables branching a single setup into many `when` scenarios.

## Architecture

```
Datadog/IntegrationUnitTests/
├── AppRunner/                    # The micro-framework
│   ├── AppRunner.swift           # Test harness — simulates app environment + SDK lifecycle
│   ├── AppRun.swift              # Fluent chain builder (given/when/and/then)
│   ├── AppRunStep.swift          # Single step abstraction (closure wrapper)
│   └── AppRunStep+Fixtures.swift # Predefined steps (launch, time, views, events, etc.)
└── RUM/                          # RUM integration tests using the framework
    ├── RUMSessionTestsBase.swift # Base class with shared fixtures and session builders
    ├── RUMSessionStartInForegroundTests.swift
    ├── RUMSessionStartInBackgroundTests.swift
    ├── RUMSessionStopTests.swift
    ├── RUMSessionTimeOutTests.swift
    ├── RUMSessionWithNoViewTests.swift
    ├── RUMSessionTrackingTests.swift
    └── SDKMetrics/               # SDK metric integration tests
```

## Core Components

### `AppRunner` — The Test Harness

`AppRunner` simulates an iOS app process. It manages these mocks:

| Mock | Purpose |
|------|---------|
| `DateProviderMock` | Simulates current time; advanced via `advanceTime(by:)` |
| `AppStateProviderMock` | Tracks simulated app state (active/inactive/background) |
| `AppLaunchHandlerMock` | Presets process launch type (user, prewarm, background) |
| `NotificationCenter` | Private instance for simulating lifecycle notifications |
| `ProcessInfoMock` | Simulates environment variables (e.g., `ActivePrewarm`) |

**API categories:**

1. **App lifecycle** — `launch(_:)`, `transitionToActive()`, `transitionToBackground()`, `advanceTime(by:)`, `viewDidAppear(vc:)`, `viewDidDisappear(vc:)`
2. **SDK setup** — `initializeSDK(_:)`, `enableRUM(_:)`, access `rum` monitor
3. **Data retrieval** — `recordedRUMSessions()` returns `[RUMSessionMatcher]`

### `AppRunStep` — Single Test Action

A wrapper around a `(AppRunner) -> Void` closure. Predefined steps in `AppRunStep+Fixtures.swift`:

| Step | What it does |
|------|-------------|
| `.appLaunch(type:)` | Simulates process launch |
| `.advanceTime(by:)` | Moves simulated clock forward |
| `.appBecomesActive(after:)` | Advances time, then transitions to active |
| `.appEntersBackground(after:)` | Advances time, then transitions to background |
| `.appDisplaysFirstFrame(after:)` | Simulates first frame render |
| `.enableRUM(after:sdkSetup:rumSetup:)` | Advances time, inits SDK, enables RUM |
| `.stopSession(after:)` | Advances time, calls `rum.stopSession()` |
| `.timeoutSession()` | Advances time by the session timeout duration |
| `.startManualView(after:viewName:viewKey:)` | Starts a manual RUM view |
| `.stopManualView(after:viewKey:)` | Stops a manual RUM view |
| `.startAutomaticView(after:viewController:)` | Simulates `viewDidAppear` for UIKit auto-tracking |
| `.stopAutomaticView(after:viewController:)` | Simulates `viewDidDisappear` |
| `.trackTwoActions(after1:after2:)` | Tracks two custom actions |
| `.trackResource(after:duration:)` | Starts and stops a resource |
| `.trackTwoLongTasks(after1:after2:)` | Tracks two long tasks |
| `.startResource(after:key:url:)` | Starts a resource (without stopping) |
| `.stopResource(after:key:)` | Stops a previously started resource |
| `.flushDatadogContext()` | Synchronizes on the context provider queue |

### `AppRun` — Composable Test Grammar

Chains `AppRunStep`s into a scenario using a fluent API:

```swift
// Build scenario
let run = AppRun
    .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: Date())))
    .and(.enableRUM(after: 0.5))
    .and(.appBecomesActive(after: 0.5))
    .when(.startManualView(after: 0, viewName: "MyView"))
    .and(.trackTwoActions(after1: 0.5, after2: 0.5))

// Execute and verify
let session = try run.then().takeSingle()
```

**Composability** — Define a shared `given` and branch into multiple `when` scenarios:

```swift
let given = AppRun
    .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: date)))
    .and(.enableRUM(after: 0.5))
    .and(.appBecomesActive(after: 0.5))

// Branch into different scenarios
let when1 = given.when(.trackTwoActions(after1: 0.5, after2: 0.5))
let when2 = given.when(.trackResource(after: 0.5, duration: 0.5))
let when3 = given.when(.trackTwoLongTasks(after1: 0.5, after2: 0.5))

for when in [when1, when2, when3] {
    let session = try when.then().takeSingle()
    XCTAssertEqual(session.views.count, 1)
}
```

### `RUMSessionTestsBase` — Shared Fixtures

Base `XCTestCase` subclass providing:

- **Time fixtures**: `processLaunchDate`, `timeToSDKInit`, `timeToAppBecomeActive`, `dt1`–`dt7`, `accuracy`
- **View name constants**: `applicationLaunchViewName`, `backgroundViewName`, `manualViewName`, `automaticViewName`
- **Session builders** — preconfigured `AppRun` chains for common starting points:

| Builder | Session shape |
|---------|-------------|
| `userSession()` | `[FG:ApplicationLaunch]` |
| `userSessionWithAutomaticView()` | `[FG:ApplicationLaunch] → [FG:AutomaticView]` |
| `userSessionWithManualView()` | `[FG:ApplicationLaunch] → [FG:ManualView]` |
| `backgroundSession()` | `[BG:(no view)]` |
| `backgroundSessionWithResource(...)` | `[BG:Background]` |
| `prewarmedSession()` | `[BG:(no view)]` (prewarm) |
| `prewarmedSessionWithResource(...)` | `[BG:Background]` (prewarm) |

All builders accept an optional `rumSetup:` closure for custom RUM configuration.

### Verification Helpers

Results are verified through `RUMSessionMatcher` (from `TestUtilities`):

```swift
let sessions = try run.then()           // Returns [RUMSessionMatcher]
let session = try sessions.takeSingle() // Asserts exactly 1 session
let (s1, s2) = try sessions.takeTwo()   // Asserts exactly 2 sessions
```

Key `RUMSessionMatcher` properties:
- `sessionStartDate`, `duration`, `sessionPrecondition`
- `ttidEvent`, `timeToInitialDisplay`
- `views` — array of view matchers, each with `name`, `duration`, `actionEvents`, `resourceEvents`, `longTaskEvents`

Use `DDAssertEqual(_:_:accuracy:)` for time comparisons (unwraps optionals and compares with tolerance).

## How to Add New Test Coverage

### 1. Adding tests to existing scenarios

If your test fits an existing category (e.g., session stop, timeout, background launch), add it to the corresponding test class. Subclass `RUMSessionTestsBase` and use its builders:

```swift
class RUMSessionStopTests: RUMSessionTestsBase {
    func testGivenUserSession_whenItIsStopped_andActionIsTrackedInForeground() throws {
        // Use preconfigured session builders
        let given1 = userSession()
        let given2 = userSessionWithAutomaticView()

        for given in [given1, given2] {
            let when = given
                .when(.stopSession(after: dt1))
                .and(.trackTwoActions(after1: dt2, after2: dt3))

            let (session1, session2) = try when.then().takeTwo()
            // Assert session1 (stopped) and session2 (restarted)...
        }
    }
}
```

### 2. Adding a new test category

Create a new `XCTestCase` subclass inheriting from `RUMSessionTestsBase`:

```swift
// RUM/MyNewScenarioTests.swift
import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

class MyNewScenarioTests: RUMSessionTestsBase {
    func testMyScenario() throws {
        let given = userSession()
        let when = given
            .when(.startManualView(after: dt1, viewName: "MyView"))
            .and(.trackTwoActions(after1: dt2, after2: dt3))

        let session = try when.then().takeSingle()
        XCTAssertEqual(session.views.count, 2)
    }
}
```

Add the file to the `Datadog.xcodeproj` under the `IntegrationUnitTests` target.

### 3. Adding a new `AppRunStep`

When existing steps don't cover your use case, add a new static factory in `AppRunStep+Fixtures.swift`:

```swift
extension AppRunStep {
    static func trackError(after dt: TimeInterval, message: String) -> AppRunStep {
        return AppRunStep({ app in
            app.advanceTime(by: dt)
            app.rum.addError(message: message, type: nil, source: .source, attributes: [:])
        })
    }
}
```

Follow the convention:
- Name describes the action (`trackX`, `startX`, `stopX`, `appX`)
- First parameter is typically `after dt: TimeInterval` for time advancement
- The closure receives `AppRunner` and calls its public methods

### 4. Adding new `AppRunner` capabilities

If you need to simulate something the `AppRunner` doesn't support yet (e.g., network state changes, user info updates):

1. Add the necessary mock to `AppRunner`'s properties
2. Inject it during `launch(_:)` or `initializeSDK(_:)`
3. Add a public method to `AppRunner` (e.g., `func changeNetworkState(to:)`)
4. Add a corresponding `AppRunStep` factory in `AppRunStep+Fixtures.swift`

### 5. Adding a new session builder to `RUMSessionTestsBase`

When you have a recurring session setup pattern, add it as a method in `RUMSessionTestsBase`:

```swift
/// Starts session with manual view that enters background and returns to foreground.
/// ```
/// [FG:ApplicationLaunch] → [FG:ManualView] → [BG] → [FG:ManualView]
/// ```
func userSessionWithBackgroundReturn(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
    return userSessionWithManualView(rumSetup: rumSetup)
        .and(.appEntersBackground(after: timeToAppEnterBackground))
        .and(.appBecomesActive(after: 1.0))
}
```

## Extending to Other Products

The `AppRunner` framework is product-agnostic. While currently used for RUM, it can be extended for **Logs**, **Trace**, **Crash Reporting**, etc.:

1. Add `enableLogs(_:)` / `enableTrace(_:)` methods to `AppRunner`
2. Add retrieval methods (e.g., `recordedLogs()`)
3. Create corresponding `AppRunStep` factories
4. Create a new base class (e.g., `LogsTestsBase`) with shared fixtures
5. Place tests under `IntegrationUnitTests/Logs/`, `IntegrationUnitTests/Trace/`, etc.

## Conventions

- **Test method naming**: `testGiven<precondition>_when<action>_<and more context>()` — follows Given/When/Then structure
- **Time parameters**: Use the shared `dt1`–`dt7` constants from `RUMSessionTestsBase` for consistent, readable time deltas
- **Accuracy**: Use the shared `accuracy` constant for all time-based assertions
- **Permutation coverage**: Loop over multiple `given` setups (e.g., with/without `trackBackgroundEvents`, different launch types) and multiple `when` branches to maximize scenario coverage from a single test method
- **Session shape comments**: Document expected session shape using ASCII notation in doc comments:
  ```
  /// [FG:ApplicationLaunch] → [FG:AutomaticView] → [BG:(no view)]
  ```
