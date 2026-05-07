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
│   ├── AppRunner+Logs.swift      # Logs state plumbing: `loggers` dict, default `logger`, recordedLogs
│   ├── AppRun.swift              # Fluent chain (given/when/and/then) + AppRunResult
│   ├── AppRunStep.swift          # Step struct + SDK-agnostic step factories (lifecycle)
│   ├── AppRunStep+Core.swift     # SDK init, user info, flushDatadogContext factories
│   └── AppRunStep+RUM.swift      # RUM Use Cases (view, action, resource, session)
├── RUM/                          # RUM harness tests
│   ├── RUMSessionTestsBase.swift # Base XCTestCase: shared time fixtures + session builders
│   ├── RUMSessionStartInForegroundTests.swift
│   └── …
├── Logs/                         # Logs harness tests
│   └── …
├── RUMHarness.xctestplan
└── LogsHarness.xctestplan
```

### SDK-agnostic core + per-feature extensions

`AppRunner.swift` and `AppRunStep.swift` are SDK-agnostic — they know about app lifecycle, time, mocks, and the step grammar, but nothing about Datadog products. Each SDK product attaches itself through extensions:

- `AppRunner+<Feature>.swift` — feature-specific methods on the runner (enable, monitor accessors, retrieval, retained-object accessors). **Always present** for a feature.
- `AppRunStep+<Feature>.swift` — static factories returning `AppRunStep` for that feature's use cases. **Optional** — only added when the feature uses the typed-factory style (see *Extension styles* below). Logs, for example, has no such file.

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

    /// Default logger pinned under the `"default"` key in `loggers`.
    var logger: LoggerProtocol! {
        get { loggers["default"] }
        set { /* set or removeValue */ }
    }
}
```

This is what makes adding a new SDK product a **drop-in** operation: create `AppRunner+Trace.swift` (and optionally `AppRunStep+Trace.swift` — see *Extension styles* below), add a computed property over `state["trace"]` if the feature needs storage, register tests in a new `TraceHarness.xctestplan`. `AppRunner.swift`/`AppRunStep.swift` stay untouched.

### Extension styles: typed factories vs inline closures

A step in the chain is either a **typed factory** call or an **inline closure**. Both are first-class — `.and(_:)` and `.when(_:)` have an overload for each — and they mix freely within a single chain.

**Typed step factories.** Steps are defined as static functions on `AppRunStep` (in `AppRunStep+<Feature>.swift`) and called by name:

```swift
.and(.enableRUM(rumSetup: { $0.trackBackgroundEvents = true }))
.and(.startManualView(after: dt1, viewName: "Cart"))
```

The reader sees use-case names. Setup is centralized and reused across tests.

**Inline closures.** A closure receives the `AppRunner` and calls public SDK APIs directly — no fixture layer required:

```swift
.and { app in
    Logs.enable(in: app.core)
    app.logger = Logger.create(in: app.core)
}
.when { app in app.logger.info("user signed in") }
```

The reader sees real SDK code.

#### Tradeoffs

|  | Typed factories | Inline closures |
|---|---|---|
| **Setup cost** | A factory must be defined before first use. | None — write against the real SDK surface. |
| **Reads as** | Domain use-case names. | Real SDK code. |
| **Permutation scaling** | Excellent — one factory reused N times across tests; matrices of `given × when` stay readable. | Setup repeats at each call site; many givens × many whens makes the chain bulky. |
| **Resilience to SDK API churn** | Wrappers absorb signature changes in one place. | Each call site updates when the SDK API shifts. |
| **Learning curve** | Contributor learns the factory vocabulary. | Contributor uses the SDK API they already know. |

#### Picking a style

- **Default to inline closures** for features with a small/flat surface or shallow app-lifecycle integration. Lowest friction; trivially refactorable later.
- **Reach for typed factories** when scenarios permute heavily across launch types, app states, and timing, or when a step is a multi-step *macro* worth naming (`appBecomesActive(after:)` = `advanceTime` + `transitionToActive`).
- **Extract a factory once a pattern repeats ≥3×** — not before. Missing factories are easy to add; premature factories ossify.
- **Mix freely within a chain.** `.and(.appLaunch(...))` followed by `.and { app in Logs.enable(...) }` is the intended use of the two `.and` overloads.

Lifecycle and core steps (`appLaunch`, `advanceTime`, `appBecomesActive`, `initializeSDK`, …) are typed factories regardless of which style a feature picks — that's the SDK-agnostic backbone everyone shares.

#### How the existing features happen to use these

- **RUM** uses typed factories — its scenarios are permutation-heavy and many actions are multi-step macros, so the factory vocabulary earns its keep. See `AppRunStep+RUM.swift`.
- **Logs** uses inline closures — its surface is flat and largely orthogonal to app lifecycle, so the fixture layer was deleted. There is intentionally no `AppRunStep+Logs.swift`; `AppRunner+Logs.swift` keeps only state plumbing (`loggers` dict, `logger` IUO accessor).

These are current choices, not constraints. RUM could grow inline closures for one-off APIs; Logs could grow a factory if a recurring multi-step pattern appears. A new product picks whatever fits its surface, independent of what RUM and Logs do.

#### Object lifetime in the inline-closure style

When you create a long-lived SDK object inside a closure (e.g. a `Logger`), you **must** retain it on the `AppRunner` — typically through a typed `state[…]`-backed accessor like `app.logger = …`. If the only reference goes out of scope when the closure returns, the object can deallocate mid-test, before its events make it through the SDK pipeline; the test then sees zero recorded events with no obvious error.

```swift
// ❌ Logger deallocates after the closure returns; test sees 0 logs.
.when { app in
    Logs.enable(in: app.core)
    let logger = Logger.create(in: app.core)
    logger.info("hello")
}

// ✅ Logger pinned to runner state; survives until tearDown().
.when { app in
    Logs.enable(in: app.core)
    app.logger = Logger.create(in: app.core)
    app.logger.info("hello")
}
```

The `loggers` dict + `logger` accessor in `AppRunner+Logs.swift` exists for this reason: it pins the logger to the runner's `state`, which lives until `tearDown()` clears it. When adopting inline closures for a new feature, mirror this pattern — expose a typed accessor (`app.<thing>`) backed by `state["<key>"]` for any object that needs to outlive a single closure.

## Core Components

| Type | File | Role |
|------|------|------|
| `AppRunner` | `AppRunner.swift` | Simulates the iOS app process: process launch, app state transitions, time, mocks. Holds `state` keyed storage. |
| `AppRunStep` | `AppRunStep.swift` | Wrapper around `(AppRunner) -> Void`. Static factories live in `+Core`/`+RUM` files; features without a step file (e.g. Logs) are driven via the inline-closure overloads of `.and`/`.when`. |
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
| `initializeSDK(sdkSetup:)` | Initializes the SDK without enabling any feature. Pair with `enableRUM(rumSetup:)` and/or an inline closure that calls `Logs.enable(in: app.core)`. |
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

### Logs (no step file)

Logs uses inline closures rather than typed factories. Drive the SDK directly inside `.and { app in … }` / `.when { app in … }`:

```swift
.and { app in
    Logs.enable(in: app.core)
    app.logger = Logger.create(in: app.core)
}
.when { app in app.logger.info("user signed in") }
```

See *Extension styles* under *Architecture* for the rationale and the lifetime rule (`app.logger = …` to keep the logger alive across steps).

## How to extend

### Adding a new step within an existing feature

1. Pick the right file by feature: lifecycle → `AppRunStep.swift`, core → `+Core`, RUM → `+RUM`. (Logs uses inline closures rather than typed factories — see *Extension styles*.)
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

1. **`AppRunner+<Feature>.swift`** (always).
   - Computed properties over `state["<feature>"]` for any per-feature storage: monitor proxies, registered handlers, and — for any objects whose lifetime must outlive a single closure — typed accessors (`app.<thing> = …`). See the lifetime rule under *Extension styles*.
   - `recorded<Feature>Events()` — retrieval via `core.waitAndReturn…Matchers()`.
   - An `enable<Feature>(_:)` method if you'll wrap it in a typed factory step.
2. **`AppRunStep+<Feature>.swift`** — *only* if the feature adopts typed factories. Skip entirely for inline-closure style. See *Extension styles* for the criteria; rule of thumb: start without it, add it once a pattern repeats ≥3× or a multi-step macro emerges.
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
