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
| `DatadogTestsObserver` | Post-test integrity checks: leaked core instances, swizzling, temp dirs, DD.logger state | `DatadogCore/Tests/TestsObserver/DatadogTestsObserver.swift` |

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

## Test Scheme Configuration

### Test randomization

All test schemes have `randomExecutionOrdering = "YES"` enabled. This ensures tests don't silently depend on execution order. If a test fails only when run with its class but passes in isolation, it has an order dependency that must be fixed.

### Thread Sanitizer (TSan)

TSan is enabled on the following schemes: DatadogCore, DatadogInternal, DatadogRUM, DatadogLogs, DatadogTrace, DatadogCrashReporting, DatadogSessionReplay, DatadogWebViewTracking, DatadogFlags, and DatadogIntegrationTests (iOS + tvOS).

**DatadogProfiling is excluded** — the `ctor_profiler` / `mach_sampling_profiler` uses Mach thread suspension (`thread_suspend` / `thread_get_state`) to walk stack frames across all threads. TSan maintains its own per-thread shadow memory and intercepts threading primitives; suspending a thread at an arbitrary point while TSan's runtime is active can deadlock or corrupt TSan's internal state. The profiler also installs SIGBUS/SIGSEGV handlers via `sigaction()` for safe memory reads during stack unwinding, which conflicts with TSan's own use of those signals. Under TSan, `ctor_profiler_start_testing()` silently fails to start the Mach sampler, leaving every test stuck at `CTOR_PROFILER_STATUS_NOT_STARTED`. Do not add TSan to the DatadogProfiling scheme.

TSan adds ~30% overhead to the modules it instruments. When writing tests for these modules, ensure that:
- Mutable state accessed from URLSession callbacks or DispatchQueue blocks is protected (e.g., `NSLock`, `@ReadWriteLock`)
- Test-local arrays or counters mutated inside concurrent closures use thread-safe wrappers

## Flaky Test Investigation

### Always capture raw logs

When running tests in a loop to reproduce failures, **always save the full raw output of every run** — not just failing ones. Grep-based filtering often misses failures due to ANSI escape codes or unexpected output formats.

```bash
# Save raw output, check exit code, strip ANSI for analysis
for i in $(seq 1 30); do
  xcodebuild test \
    -workspace Datadog.xcworkspace \
    -scheme "DatadogIntegrationTests iOS" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
    > /tmp/test_run_$i.log 2>&1

  EXIT=$?
  if [ $EXIT -ne 0 ]; then
    echo "[$i] FAIL (exit $EXIT)"
    sed 's/\x1b\[[0-9;]*m//g' /tmp/test_run_$i.log | grep -E "failed|unexpected" | grep -v "0 unexpected"
  else
    echo "[$i] PASS"
  fi
done
```

### Never assume a failure is pre-existing

A test that fails during your run **may have been caused by your changes**, even if:
- The test is in a known-flaky list
- You didn't modify the test file
- The failure "looks unrelated"

Before dismissing a failure:
1. Identify the exact test name and assertion message
2. Determine whether your changes could affect that code path (e.g., test randomization changing execution order)
3. If you can't identify the test, **do not discard the log** — you won't be able to reproduce it on demand

### Reproducing flaky tests

Flaky tests often only fail in specific contexts. Test reproduction in escalating order:

| Scenario | Command | What it tests |
|---|---|---|
| Single test, isolated | `-only-testing:Scheme/Class/testMethod` | The test logic itself |
| Full test class | `-only-testing:Scheme/Class` | Intra-class order dependencies |
| Full scheme | `make test-ios SCHEME="..."` | Cross-class interference |
| Full scheme under CPU load | Run with background `bc -l` loops | CI-like resource contention |

A test that passes 30 times in isolation but fails 1/20 with its class is **order-dependent**. A test that only fails on CI may depend on simulator pool state, container memory pressure, or other environmental factors that are difficult to reproduce locally.

### Validate fixes without false confidence

Running a test once after a fix proves nothing — flaky tests can pass 50 times in a row and still fail on CI. When fixing a flaky test:

1. **Reproduce the failure first** — if you can't trigger it, you can't confirm your fix works
2. **Understand the root cause** — don't apply fixes based on speculation about what "might" cause the issue
3. **Verify the fix doesn't break other tests** — a fix to one test can introduce failures in others, especially when shared state is involved (e.g., `os_activity` scopes, singleton registries)

### Timeout semantics in tests

Not all timeouts serve the same purpose. Changing a timeout without understanding its intent can weaken the test:

| Pattern | Meaning | Safe to increase? |
|---|---|---|
| `wait(for:, timeout: 0)` | Asserts expectations were fulfilled **synchronously** before `wait` is called | **No** — this is a behavioral contract, not a safety margin |
| `wait(for:, timeout: 0.5)` | Allows async operations up to 0.5s | Yes, if the operation is genuinely async |
| `wait(during: 0.1) { ... }` | Fixed delay, then assert — `wait(during:)` is **not** a timeout, it adds wall-clock time | Increase cautiously — each bump adds real seconds to the suite |
| `waitForExpectations(timeout: 5)` | Safety ceiling for async work that should complete well under 5s | Yes — these don't slow down passing tests |

When a test uses `timeout: 0`, it is asserting that the completion handler fires synchronously. Changing it to `timeout: 1` makes the test pass even if the code path becomes async — silently breaking the contract the test was designed to verify.

### Common flakiness patterns in this codebase

| Pattern | Risk | Example |
|---|---|---|
| `DispatchQueue.concurrentPerform` with `timeout: 0.1` | `concurrentPerform` is synchronous but expectation delivery has overhead | `CTorProfilerTests`, `MachSamplingProfilerTests` |
| Watchdog/timing tests with sub-second thresholds | Thread scheduling jitter on CI exceeds the tolerance | `AppHangsWatchdogThreadTests` with 0.1s threshold |
| Unfinished `os_activity` scopes across tests | `span.setActive()` without `span.finish()` accumulates nested scopes | `RUMResourceTraceIntegrationTests` |
| Mutable state in URLSession callbacks without synchronization | URLSession delegates fire on arbitrary queues | `URLSessionTaskStateSwizzlerTests` |
| Unbounded polling loops | `while state != .ready { Thread.sleep(0.1) }` with no deadline | `WatchdogTerminationsMonitoringTests` |
| `wait(during:)` with short delays | CADisplayLink and run-loop-dependent callbacks need time to fire | `DisplayLinkerTests` |
