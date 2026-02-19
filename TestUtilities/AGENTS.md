# TestUtilities — Agent Guide

> Module-specific guidance for the shared test infrastructure. For project-wide rules, see the root `AGENTS.md`.

## Module Overview

TestUtilities provides shared mocks, fakes, helpers, and matchers used by all test targets across the SDK. It is not exported by default — enabled via `DD_TEST_UTILITIES_ENABLED` env var for integration testing.

## Mock Protocols

```swift
// Deterministic default — use when specific value doesn't matter
public protocol AnyMockable {
    static func mockAny() -> Self
}

// Randomized value — use for fuzz/property testing
public protocol RandomMockable {
    static func mockRandom() -> Self
}

// Both protocols + .mockWith(...) for customizable mocks with named parameters
```

**Conventions:**
- `.mockAny()` — returns a deterministic default
- `.mockRandom()` — returns a randomized value (for property testing)
- `.mockWith(...)` — customizable mock with named parameters for specific fields

## Key Types

| Type | Purpose | Location |
|------|---------|----------|
| `DatadogCoreProxy` | In-memory SDK instance that intercepts all events for assertions | `Sources/Proxies/DatadogCoreProxy.swift` |
| `ServerMock` | HTTP mock server for network tests | `Sources/Proxies/ServerMock.swift` |
| `HTTPClientMock` | Mock HTTP client | `Sources/Mocks/DatadogCore/HTTPClientMock.swift` |
| `PassthroughCoreMock` | Lightweight core mock that passes events through | `Sources/Mocks/DatadogInternal/PassthroughCoreMock.swift` |
| `SingleFeatureCoreMock` | Core mock for single-feature tests | `Sources/Mocks/DatadogInternal/SingleFeatureCoreMock.swift` |
| `FeatureScopeMock` | Mock feature scope for isolated testing | `Sources/Mocks/DatadogInternal/FeatureScopeMock.swift` |
| `DatadogContextMock` | Mock SDK context | `Sources/Mocks/DatadogInternal/DatadogContextMock.swift` |
| `DateProviderMock` | Deterministic date provider for time-dependent tests | `Sources/Mocks/DatadogInternal/DateProviderMock.swift` |

## Event Matchers

Typed matchers for asserting on serialized events:

| Matcher | Purpose |
|---------|---------|
| `RUMEventMatcher` | Matches individual RUM events by JSON key paths |
| `RUMSessionMatcher` | Groups RUM events by session, validates consistency |
| `LogMatcher` | Matches log events |
| `SpanMatcher` | Matches trace span events |
| `SRSegmentMatcher` | Matches Session Replay segments |
| `JSONDataMatcher` | Generic JSON data matching |

### RUMSessionMatcher Pattern

```swift
let matchers = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers)
let session = matchers[0]
let view = session.views[0]
XCTAssertEqual(view.viewEvents.count, 2)
```

## DatadogCoreProxy Usage Pattern

The standard pattern for integration-style unit tests:

```swift
// 1. Create proxy
let core = DatadogCoreProxy(context: .mockWith(service: "test-service"))
defer { core.flushAndTearDown() }  // MUST be in defer

// 2. Enable features against the proxy
RUM.enable(with: config, in: core)

// 3. Trigger actions
let monitor = RUMMonitor.shared(in: core)
monitor.startView(key: "view1")

// 4. Assert on captured events
let events = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
XCTAssertEqual(events.count, 1)
```

**Key methods:**
- `core.waitAndReturnEvents(of:ofType:)` — waits for async processing then returns typed events
- `core.flushAndTearDown()` — ensures cleanup, **must** be called in `defer`

## Directory Structure

```
Sources/
├── Helpers/      # Assert helpers, date/time utils, fuzzy helpers
├── Matchers/     # Typed event matchers (RUM, Logs, Traces, SR)
├── Mocks/        # Mock implementations organized by module
│   ├── DatadogCore/            # Core mocks
│   ├── DatadogInternal/        # Internal mocks
│   ├── DatadogRUM/             # RUM mocks
│   ├── DatadogSessionReplay/   # SR mocks
│   ├── DatadogLogs/            # Log mocks
│   ├── DatadogTrace/           # Trace mocks
│   ├── CrashReporting/         # Crash report mocks
│   └── SystemFrameworks/       # UIKit, Foundation, WebKit mocks
├── Proxies/      # Test proxies (DatadogCoreProxy, ServerMock)
└── Spies/        # Spy implementations (PrintFunctionSpy)
```

## SwiftLint Rules for Tests

Tests use separate lint rules (`tools/lint/tests.swiftlint.yml`) — more permissive than production:
- Force unwrapping (`!`) allowed
- Force try (`try!`) allowed
- Same TODO-with-JIRA requirement

## Important for Agents

- When adding a new mock, follow the `.mockAny()` / `.mockRandom()` / `.mockWith(...)` conventions
- Place mocks in the correct subdirectory under `Mocks/` (organized by module)
- Prefer extending existing mock types over creating new ones
- Use `DatadogCoreProxy` for any test that needs to verify events are written correctly

## Test Design Principles

- **Determinism**: Use `DateProviderMock` for time-dependent tests, deterministic UUIDs where needed, `HTTPClientMock`/`ServerMock` for network isolation. No `sleep()` in unit tests — use expectations or synchronous test queues.
- **Fuzzy/property testing**: `RandomMockable` protocol + `FuzzyHelpers` for random input generation to catch edge cases.
- **Assertions**: `XCTAssertEqual` for values, custom `DDAssert` helpers in `Sources/Helpers/DDAssert.swift`, `XCTestExpectation` for async operations, event matchers for structured assertions.

## Reference Documentation

- Root `AGENTS.md` — Project-wide rules and test conventions
