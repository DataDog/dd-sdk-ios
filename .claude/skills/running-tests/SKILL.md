---
name: dd-sdk-ios:running-tests
description: Use when asked to run tests in the dd-sdk-ios project — whether a full module suite, a specific test class, or a single test method. Use when choosing between make, xcodebuild, or Xcode MCP for running iOS/tvOS/visionOS tests.
---

# Running Tests in dd-sdk-ios

## Two Approaches

### 1. Makefile — CI workflows, full module suites

Use `make` to replicate CI exactly. Always prefer this for running a full module or all modules.

**Before running:** verify available simulators and pick an appropriate device name:
```bash
xcrun simctl list devices available | grep -E "iPhone|Apple TV"
```

| Goal | Command |
|------|---------|
| All iOS unit tests | `make test-ios-all` |
| One module | `make test-ios SCHEME="<Scheme>"` |
| One module with specific device | `make test-ios SCHEME="<Scheme>" DEVICE="<Device>"` |
| All tvOS unit tests | `make test-tvos-all` |
| UI / integration tests | `make ui-test TEST_PLAN="<Plan>"` |
| Session Replay snapshots | `make sr-snapshot-test` |

**Default devices** (authoritative values from Makefile):
```bash
grep "DEFAULT_" Makefile
```

Always pass `DEVICE=` explicitly if the default simulator is not installed locally. Check `xcrun simctl list devices available` first.

**Module scheme names:** Always read the `Makefile` to get the authoritative list — it changes as modules are added or renamed:
```bash
grep "test-ios-all" Makefile -A 20  # shows all iOS schemes used in CI
```

### 2. Xcode MCP — selective, fast, single test or class

Discover the actual connected tool schemas first; a missing legacy tool name does
not mean MCP is disabled. Inspect `xcode-select -p` and `xcodebuild -version`, then
compare the intended toolchain with the bridge's workspace/destination. Do not
change the user's default command-line tools to repair a mismatch.

**Discover and target the workspace:**
```
XcodeListWorkspaces()  # match the returned path to the intended workspace
XcodeListSchemes(workspaceIdentifier: <discovered workspace>)
```

If no intended workspace is open, use `XcodeOpenWorkspace` with its verified
absolute project/workspace path, then use the returned identifier. Handle an
actual access prompt if one occurs; do not request configuration changes just
because an older tool such as `XcodeListWindows` is absent. Older bridges may
expose `tabIdentifier`; use that only when their live schema actually requires it.

`RunSomeTests` uses the active scheme and test plan. After securing the build/test
lane, select the discovered scheme with `XcodeSwitchScheme(workspaceIdentifier,
schemeName)` if needed. Inspect its returned destination and active test plan;
scheme changes can select a different platform variant. Use
`XcodeListRunDestinations`, `XcodeSwitchRunDestination`, `XcodeListTestPlans` and
`XcodeSwitchTestPlan` when supported by the connected bridge. Do not change a
workspace another task is using. If scheme selection is unavailable, use the
explicit CLI fallback below rather than requiring a manual switch.

**Discover exact selected tests:**
```
GetTestList(workspaceIdentifier: <discovered workspace>)
```
Read `fullTestListPath` if the inline list is truncated. Use returned target names
and identifiers; do not infer them from a historical naming convention.

**If the test is in the active scheme**, run it directly:
```
RunSomeTests(
  workspaceIdentifier: <discovered workspace>,
  tests: [{
    targetName: "<targetName from GetTestList>",
    testIdentifier: "<identifier from GetTestList>"
  }]
)
```

**CLI fallback**, using an explicitly discovered scheme and destination:
```bash
xcodebuild test \
  -workspace Datadog.xcworkspace \
  -scheme "<discovered scheme>" \
  -destination 'platform=<Platform> Simulator,name=<Device>' \
  -only-testing:<TargetName>/<TestClass>/<testMethod>
```

To find which module owns a test:
```
XcodeGrep(workspaceIdentifier: <discovered workspace>, pattern: "func <testName>", outputMode: "filesWithMatches")
# Locate the module, then discover its actual scheme and test identifier.
```

## Decision Guide

```
Need to run tests?
├── Full module or CI replication?
│   └── make test-ios SCHEME="<discovered scheme>" DEVICE="<Device>"
└── Specific class or method?
    ├── Test is in the active Xcode scheme? (check GetTestList)
    │   └── RunSomeTests
    └── Test is in a different scheme?
        └── XcodeSwitchScheme and rediscover tests, or xcodebuild -only-testing
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Assuming `RunSomeTests` works for any module | Select the discovered scheme/test plan, then rediscover its tests |
| Not knowing which scheme owns the test | Grep for the function — file path reveals the module |
| Running full module when only one test needed | Use `RunSomeTests` or `xcodebuild -only-testing` |
| Running integration tests under feature module scheme | Integration tests use target `DatadogIntegrationTests iOS/tvOS` |
