# Testing Guide

## Test Conventions

- **Follow existing patterns** — Look at sibling test files for conventions
- Use `TestUtilities` for mocks and helpers
- Do not test Apple frameworks
- Do not test purely generated code
- Do not mock DatadogCore incorrectly (use provided helpers)
- No `sleep()` in unit tests — use expectations or synchronous test queues

## Mock Infrastructure

| Convention | Usage | Example |
|------------|-------|---------|
| `.mockAny()` | Deterministic default — use when specific value doesn't matter | `DatadogContext.mockAny()` |
| `.mockRandom()` | Randomized value — use for fuzz/property testing | `String.mockRandom()` |
| `.mockWith(...)` | Customizable mock with named parameters for specific fields | `.mockWith(service: "test")` |

## Key Test Types

| Type | Purpose | Location |
|------|---------|----------|
| `DatadogCoreProxy` | In-memory SDK instance that intercepts all events for assertions | `TestUtilities/Sources/Proxies/DatadogCoreProxy.swift` |
| `ServerMock` | HTTP mock server for network tests | `TestUtilities/Sources/Proxies/ServerMock.swift` |
| `HTTPClientMock` | Mock HTTP client | `TestUtilities/Sources/Mocks/DatadogCore/` |
| `PassthroughCoreMock` | Lightweight core mock that passes events through | `TestUtilities/Sources/Mocks/DatadogInternal/` |
| `FeatureScopeMock` | Mock feature scope for isolated testing | `TestUtilities/Sources/Mocks/DatadogInternal/` |
| `RUMSessionMatcher` | Groups RUM events by session, validates consistency | `TestUtilities/Sources/Matchers/` |

## DatadogCoreProxy Usage Pattern

```swift
let core = DatadogCoreProxy(context: .mockWith(service: "test-service"))
defer { core.flushAndTearDown() }  // MUST be in defer

RUM.enable(with: config, in: core)
let monitor = RUMMonitor.shared(in: core)
monitor.startView(key: "view1")
monitor.stopView(key: "view1")

let session = try RUMSessionMatcher
    .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
    .takeSingle()

let views = try session.views.dropApplicationLaunchView()
XCTAssertEqual(views.count, 1)
XCTAssertEqual(views[0].name, "view1")
```

### ApplicationLaunch View

The SDK auto-generates a synthetic **"ApplicationLaunch"** view to capture events that occur before the first user view starts. Almost every RUM integration test must account for this:

```swift
// Strip the ApplicationLaunch view (throws if it's missing — serves as an assertion too)
let views = try session.views.dropApplicationLaunchView()

// Or assert-then-index when you need to inspect the launch view itself
XCTAssertTrue(session.views[0].isApplicationLaunchView())
let userViews = Array(session.views.dropFirst())
```

Related helpers on `RUMSessionMatcher.View`:
- `isApplicationLaunchView()` — checks `name == "ApplicationLaunch"` and `path == "com/datadog/application-launch/view"`
- `isBackgroundView()` — checks for the synthetic "Background" view

## SwiftLint for Tests

Tests use separate lint rules (`tools/lint/tests.swiftlint.yml`) — force unwrapping and force try are allowed. Same TODO-with-JIRA requirement applies.
