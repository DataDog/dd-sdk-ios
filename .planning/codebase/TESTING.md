# Testing — dd-sdk-ios

## Test Framework

- **Unit tests:** XCTest (standard Apple framework)
- **Snapshot tests:** Custom snapshot infrastructure for Session Replay
- **No third-party test frameworks** in production test targets

## Test Organization

### Directory Structure

```
<Module>/Tests/              # Unit tests per module
TestUtilities/Sources/       # Shared test infrastructure
  ├── Helpers/               # Assert helpers, date/time utils, fuzzy helpers
  ├── Matchers/              # Typed event matchers (RUM, Logs, Traces, SR)
  ├── Mocks/                 # Mock implementations organized by module
  │   ├── DatadogCore/       # Core mocks (HTTPClientMock, DirectoriesMock)
  │   ├── DatadogInternal/   # Internal mocks (DatadogContextMock, FeatureScopeMock)
  │   ├── DatadogRUM/        # RUM mocks (RUMFeatureMocks, VitalMocks)
  │   ├── DatadogSessionReplay/  # SR mocks (RecorderMocks, SnapshotProcessorSpy)
  │   ├── DatadogLogs/       # Log mocks
  │   ├── DatadogTrace/      # Trace mocks
  │   ├── CrashReporting/    # Crash report mocks
  │   └── SystemFrameworks/  # UIKit, Foundation, WebKit mocks
  ├── Proxies/               # Test proxies (DatadogCoreProxy, ServerMock)
  └── Spies/                 # Spy implementations (PrintFunctionSpy)
IntegrationTests/            # UI-based integration tests (CocoaPods workspace)
E2ETests/                    # End-to-end tests against real backend
SmokeTests/                  # Integration manager smoke tests (SPM, CocoaPods, Carthage)
BenchmarkTests/              # Performance measurement tests
DatadogSessionReplay/SRSnapshotTests/  # Visual snapshot tests
```

### Test File Naming

- `<ClassName>Tests.swift` — standard unit test file
- Module test directories mirror source structure

## Mock Infrastructure

### Core Protocols

```swift
// TestUtilities/Sources/Mocks/Mockable.swift
public protocol AnyMockable {
    static func mockAny() -> Self    // Returns a deterministic default mock
}

public protocol RandomMockable {
    static func mockRandom() -> Self // Returns a randomized mock for fuzzy testing
}
```

### Key Mock Types

| Mock | Purpose | Location |
|------|---------|----------|
| `DatadogCoreProxy` | Intercepts all events written to core for assertions | `TestUtilities/Sources/Proxies/DatadogCoreProxy.swift` |
| `ServerMock` | HTTP mock server for network tests | `TestUtilities/Sources/Proxies/ServerMock.swift` |
| `HTTPClientMock` | Mock HTTP client | `TestUtilities/Sources/Mocks/DatadogCore/HTTPClientMock.swift` |
| `PassthroughCoreMock` | Lightweight core mock that passes events through | `TestUtilities/Sources/Mocks/DatadogInternal/PassthroughCoreMock.swift` |
| `SingleFeatureCoreMock` | Core mock for single-feature tests | `TestUtilities/Sources/Mocks/DatadogInternal/SingleFeatureCoreMock.swift` |
| `FeatureScopeMock` | Mock feature scope for isolated testing | `TestUtilities/Sources/Mocks/DatadogInternal/FeatureScopeMock.swift` |
| `DatadogContextMock` | Mock SDK context | `TestUtilities/Sources/Mocks/DatadogInternal/DatadogContextMock.swift` |
| `DateProviderMock` | Deterministic date provider | `TestUtilities/Sources/Mocks/DatadogInternal/DateProviderMock.swift` |

### Mock Conventions

- `.mockAny()` — deterministic default, used when the specific value doesn't matter
- `.mockRandom()` — randomized value, used for fuzz/property testing
- `.mockWith(...)` — customizable mock with named parameters for specific fields
- Mocks are in `TestUtilities` target, shared across all test targets

## Matchers

### Event Matchers

Typed matchers for asserting on serialized events:

| Matcher | Purpose |
|---------|---------|
| `RUMEventMatcher` | Matches individual RUM events by JSON key paths |
| `RUMSessionMatcher` | Groups RUM events by session, validates consistency |
| `LogMatcher` | Matches log events |
| `SpanMatcher` | Matches trace span events |
| `SRSegmentMatcher` | Matches Session Replay segments |
| `SRRequestMatcher` | Matches Session Replay HTTP requests |
| `JSONDataMatcher` | Generic JSON data matching |
| `JSONObjectMatcher` | Generic JSON object matching |

### RUMSessionMatcher Pattern

```swift
// Groups events by session, validates session consistency
let matchers = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers)
let session = matchers[0]
// Access grouped view visits
let view = session.views[0]
XCTAssertEqual(view.viewEvents.count, 2)
```

## Test Proxy Pattern

### DatadogCoreProxy

The primary integration test pattern — wraps real `DatadogCore` to intercept events:

```swift
let core = DatadogCoreProxy(context: .mockWith(service: "test-service"))
defer { core.flushAndTearDown() }

// Enable features against the proxy
RUM.enable(with: config, in: core)

// Trigger actions...
let monitor = RUMMonitor.shared(in: core)
monitor.startView(key: "view1")

// Assert on captured events
let events = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
XCTAssertEqual(events.count, 1)
```

### Key Methods

- `core.waitAndReturnEvents(of:ofType:)` — waits for async processing then returns typed events
- `core.flushAndTearDown()` — ensures cleanup, must be called in `defer`

## Test Design Principles

### Determinism

- **Fake clock:** `DateProviderMock` for time-dependent tests
- **Fake UUID:** Deterministic UUID generation where needed
- **Fake transport:** `HTTPClientMock` / `ServerMock` for network isolation
- **No `sleep()` in unit tests:** Use expectations or synchronous test queues

### Fuzzy/Property Testing

- `RandomMockable` protocol for generating random test data
- `FuzzyHelpers` for random string/number generation
- Tests exercise code paths with randomized inputs to catch edge cases

### Assertions

- `XCTAssertEqual` for value comparisons
- Custom `DDAssert` helpers in `TestUtilities/Sources/Helpers/DDAssert.swift`
- `XCTestExpectation` for async operations
- Event matchers for structured event assertions

### SwiftLint for Tests (`tools/lint/tests.swiftlint.yml`)

Separate lint rules for test code (more permissive than sources):
- Force unwrapping allowed in tests
- Force try allowed in tests
- Same TODO-with-JIRA requirement

## Running Tests

### Unit Tests

```bash
# All iOS unit tests
make test-ios-all

# Specific module
make test-ios SCHEME="DatadogRUM iOS"

# Single test
xcodebuild test -workspace Datadog.xcworkspace \
  -scheme "DatadogCore iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:DatadogCoreTests/SpecificTestClass/testMethod
```

### Integration Tests

```bash
make ui-test TEST_PLAN="Default"
make ui-test-all
```

### Session Replay Snapshots

```bash
make sr-snapshots-pull     # Pull reference images
make sr-snapshot-test      # Run snapshot comparison
make sr-snapshots-push     # Update reference images
```

## Test Coverage

- Each module has comprehensive unit tests in `<Module>/Tests/`
- Integration tests in `IntegrationTests/` test cross-module interactions
- E2E tests validate data flow to real Datadog backend (daily CI runs)
- Smoke tests verify each dependency manager integration works
- No explicit code coverage target enforced, but new features require tests
