---
name: dd-sdk-ios:add-harness-test
description: Use when adding a black-box behavioural test (harness test) for any SDK feature using the AppRunner micro-framework. Use when the user describes a behaviour scenario in given/when/then form and expects a test under Datadog/IntegrationUnitTests/ registered in a *Harness.xctestplan.
---

# Adding a Harness Test in dd-sdk-ios

## When to use

A **harness test** drives the real SDK through public APIs against a simulated app environment (`AppRunner`). Tests live under `Datadog/IntegrationUnitTests/<Feature>/` and run via the `TestHarness` scheme + a `<Feature>Harness.xctestplan`.

Use this skill when the user asks for a test that:
- Verifies SDK behaviour (not implementation), expressed as `given X / when Y / then Z`.
- Should run sub-second and use only public APIs.
- Belongs in a `*Harness.xctestplan`, not a per-module unit test target.

For full architecture and step catalog, see `docs/HARNESS_TESTING.md`.

## Decision tree

| Feature in scenario | Test folder | Test base | Test plan |
|---|---|---|---|
| RUM (views, actions, resources, sessions) | `Datadog/IntegrationUnitTests/RUM/` | Inherit `RUMSessionTestsBase` to reuse `dt1`–`dt7`, `accuracy`, session builders | `RUMHarness.xctestplan` |
| Logs (logger APIs, log content, RUM↔Logs bundling) | `Datadog/IntegrationUnitTests/Logs/` | `XCTestCase` directly (no base — Logs has no shared session shape) | `LogsHarness.xctestplan` |
| New product (Trace, Crash, …) | New folder | First read `docs/HARNESS_TESTING.md` "How to extend" — drop-in pattern: pair of `AppRunner+<Feature>.swift` / `AppRunStep+<Feature>.swift` files, no edits to `AppRunner.swift` |  New `<Feature>Harness.xctestplan` |

## Workflow

1. **Translate the scenario into `given/when/then`.** Identify the precondition (process launch type, SDK + features enabled, app state, time elapsed), the action under test, and the expected outcome.
2. **Pick the right step files for fixtures.** Lifecycle steps live in `AppRunStep.swift`; core (SDK init, user info, flush) in `AppRunStep+Core.swift`; RUM in `AppRunStep+RUM.swift`; Logs in `AppRunStep+Logs.swift`. Check whether the action is already covered. If not, add a static factory in the file matching the feature — name it `trackX`/`startX`/`stopX`/`appX`, first parameter typically `after dt: TimeInterval`.
3. **For RUM scenarios — check `RUMSessionTestsBase` builders.** `userSession()`, `userSessionWithManualView()`, `userSessionWithAutomaticView()`, `backgroundSession()`, `prewarmedSession()` (and `…WithResource` variants). Reuse if it fits; if you find yourself writing a recurring shared-`given` shape twice, add a builder there.
4. **Write the test.** Naming: `testGiven<precondition>_when<action>_<and more context>()`. Branch a single `given` into multiple `when`s when permutations are cheap.
5. **Add the file to the project.** Use the `dd-sdk-ios:xcode-file-management` skill (Xcode MCP) — it updates `.pbxproj` atomically. Target membership is inferred from path: anything under `Datadog/IntegrationUnitTests/` joins `DatadogIntegrationTests`.
6. **Register the test method in the `*Harness.xctestplan`.** The plan whitelists individual methods via `selectedTests`. Add an entry like `"<TestClass>/<testMethod>()"`.
7. **Run.** `make test-ios SCHEME="TestHarness" TEST_PLAN="LogsHarness"` (or `RUMHarness`). See `dd-sdk-ios:running-tests` for selective single-test execution via Xcode MCP.

## Conventions

- **Time deltas.** Use shared `dt1`–`dt7` from `RUMSessionTestsBase`. Logs tests not inheriting from it should declare their own equivalents at the top of the test class (see `LogsBasicTests.swift`).
- **Accuracy.** Use shared `accuracy`; pair with `DDAssertEqual(_:_:accuracy:)` (unwraps optionals, compares with tolerance).
- **Session shape.** Document in doc comment using ASCII: `[FG:ApplicationLaunch] → [FG:ManualView] → [BG:(no view)]`.
- **Permutation coverage.** Loop over multiple `given`s and multiple `when`s to multiply scenarios from one method.
- **`then()` results.** `result.sessions.takeSingle()` / `takeTwo()` for exact-count assertions; `result.logs[i]` direct access. Features not enabled in the scenario return empty arrays — no need to guard.

## Mini-examples

Logs (`Datadog/IntegrationUnitTests/Logs/LogsBasicTests.swift`):

```swift
func testGivenLogsEnabled_whenInfoIsLogged_itIsRecorded() throws {
    let when = AppRun
        .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
        .and(.advanceTime(by: timeToSDKInit))
        .and(.initializeSDK())
        .and(.enableLogs())
        .and(.createLogger())
        .and(.appBecomesActive(after: timeToAppBecomeActive))
        .and(.advanceTime(by: dt1))
        .when(.withLogger { $0.info("user signed in") })

    let result = try when.then()
    XCTAssertEqual(result.logs.count, 1)
    result.logs[0].assertStatus(equals: "info")
    result.logs[0].assertMessage(equals: "user signed in")
}
```

RUM (using a `RUMSessionTestsBase` builder):

```swift
func testGivenUserSession_whenItIsStopped_andActionIsTrackedInForeground() throws {
    let given1 = userSession()
    let given2 = userSessionWithAutomaticView()

    for given in [given1, given2] {
        let when = given
            .when(.stopSession(after: dt1))
            .and(.trackTwoActions(after1: dt2, after2: dt3))

        let (session1, session2) = try when.then().sessions.takeTwo()
        // assert session1 (stopped) and session2 (restarted) …
    }
}
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Test compiles but never runs in CI | Add `<TestClass>/<testMethod>()` to `selectedTests` in the `*Harness.xctestplan`. |
| Used `XCTestCase` for a RUM scenario, then re-declared `dt1`/`accuracy` | Inherit `RUMSessionTestsBase` instead — gives time deltas, accuracy, and session builders for free. |
| Wrote a new step factory when an existing one fit | Search `AppRunStep+RUM.swift` / `+Logs.swift` first; for Logs APIs the existing `withLogger { $0.<api>(...) }` covers any `LoggerProtocol` method. |
| Combined `enableRUM(after:sdkSetup:rumSetup:)` (does init internally) with a separate `initializeSDK` step | Use either the `enableRUM(after:…)` convenience **or** `initializeSDK` + `enableRUM(rumSetup:)` — never both. |
| Added the new step factory in `AppRunStep.swift` instead of the feature file | Lifecycle (process launch, time, app state) only in `AppRunStep.swift`; everything else in the feature-specific file. |
| Touched `AppRunner.swift` to add per-feature storage | Use `state[...]` + computed property in the feature extension. See `core` / `loggers` for the pattern. |
| Created the file with `Write` / `mv` | Use `dd-sdk-ios:xcode-file-management` (Xcode MCP) so `.pbxproj` stays in sync. |

## Pointer

For full architecture (SDK-agnostic core + per-feature extensions, anonymous `state` storage, `AppRunResult` shape) and the complete step catalog, see `docs/HARNESS_TESTING.md`.
