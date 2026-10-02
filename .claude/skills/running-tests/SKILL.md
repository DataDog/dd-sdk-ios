---
name: dd-sdk-ios:running-tests
description: Use when asked to run tests in the dd-sdk-ios project — whether a full module suite, a specific test class, or a single test method. Use when choosing between make, xcodebuild, or Xcode MCP for running iOS/tvOS/visionOS tests, or when tests must run under a different scheme, simulator, or test plan.
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

**Module scheme names:** schemes are multiplatform and named after the module (`DatadogCore`, `DatadogRUM`, …) — no platform suffix. Read the `Makefile` for the authoritative list:
```bash
grep "test-ios-all" Makefile -A 20  # shows all iOS schemes used in CI
```

### 2. Xcode MCP — selective, fast, single test or class

Requires **Xcode 27** with the Xcode MCP server connected (`claude mcp add --transport stdio xcode -- xcrun mcpbridge`).

**Setup (once per session):**
- The `mcp__xcode__*` tools are deferred. Load them by exact name — `ToolSearch("select:mcp__xcode__XcodeOpenWorkspace,mcp__xcode__XcodeSwitchScheme,mcp__xcode__GetTestList,mcp__xcode__RunSomeTests,...")`. A `+xcode` keyword search misses tools without "Xcode" in their name (`GetTestList`, `RunSomeTests`).
- If the tools are missing entirely → ask the user to enable "Allow external agents to use Xcode tools" in Xcode Intelligence settings and reconnect with `/mcp`.

```
XcodeOpenWorkspace(path: "<repo>/Datadog.xcworkspace")
# → workspaceIdentifier e.g. "workspace-sMg5URZMpB", plus activeScheme / activeRunDestination
```
- If the agent isn't approved yet, every tool fails with *"This agent isn't approved to use Xcode's tools yet"*. `XcodeOpenWorkspace` triggers the approval prompt in Xcode (no prompt if already approved).
- **Pass `workspaceIdentifier` to every other call.** The schema marks it optional, but calls fail without it. Despite the schema, an absolute path is rejected (*"Unknown workspace identifier"*) — use the returned identifier.

**1. Find the module that owns the test** — the path reveals it:
```
XcodeGrep(workspaceIdentifier: <id>, pattern: "func <testName>", outputMode: "filesWithMatches")
# → Datadog/DatadogLogsTests/... → scheme "DatadogLogs", target "DatadogLogsTests"
```
Ignore a stray `"No matches found"` string mixed into real results.

**2. Record the user's state, then select the scheme.** Testing tools only see the active scheme.
```
XcodeListSchemes(workspaceIdentifier: <id>)           # note activeSchemeName
XcodeListRunDestinations(workspaceIdentifier: <id>)   # note activeDestinationDisplayTitle
XcodeSwitchScheme(workspaceIdentifier: <id>, schemeName: "DatadogLogs")
```

**3. Select a run destination.** Schemes are multiplatform; the active destination is often `My Mac`. Switch to a simulator for iOS/tvOS behavior:
```
XcodeSwitchRunDestination(workspaceIdentifier: <id>, displayTitle: "iPhone 17 Pro (27.0)")
```
- Pass a `displayTitle` exactly as listed — titles aren't uniform (`"iPhone 17 Pro (27.0)"` vs `"iPhone 18 Pro"`).
- Prefer the Makefile default device (`grep DEFAULT_IOS_DEVICE Makefile`) on the newest OS.
- The inline list is capped at 40; the full list is in `fullRunDestinationListPath` (readable with `Read`/`grep`).
- `XcodeSwitchScheme` may change the destination on its own — check `activeDestinationDisplayTitle` in its response.

**4. Get the test identifier.**
```
GetTestList(workspaceIdentifier: <id>)
```
Test targets are `<Module>Tests` (e.g. `DatadogLogsTests`, `DatadogIntegrationTests`). Identifiers look like `<TestClass>/<testMethod>()`. If the response is `truncated` (capped at 100), grep `fullTestListPath` for `TEST_IDENTIFIER` / `TEST_FILE_PATH`.

**5. Run.** Blocks until results are in:
```
RunSomeTests(
  workspaceIdentifier: <id>,
  tests: [{ targetName: "DatadogLogsTests", testIdentifier: "<TestClass>/<testMethod>()" }]
)
RunAllTests(workspaceIdentifier: <id>)   # every test in the active scheme / test plan
```
Results include per-test state, `errorMessages`, `fullConsoleLogsPath`, and an `xcresultBundlePath`.

**If the build fails before tests run:**
```
GetBuildLog(workspaceIdentifier: <id>, severity: "error")
```
For the full build-and-fix loop, see the `dd-sdk-ios:build-and-diagnose` skill.

**Test plans:** module schemes don't use test plans (`XcodeListTestPlans` → `usesTestPlans: false`). If a scheme does, switch with `XcodeSwitchTestPlan` before running.

**6. Restore the user's state.** Switches persist in Xcode. Switch back to the recorded scheme, **then** the recorded destination — the scheme switch carries the current destination over.

### 3. xcodebuild fallback — no Xcode MCP

```bash
xcodebuild test \
  -workspace Datadog.xcworkspace \
  -scheme "<Module>" \
  -destination 'platform=<Platform> Simulator,name=<Device>' \
  -only-testing:<Module>Tests/<TestClass>/<testMethod>
```

## Decision Guide

```
Need to run tests?
├── Full module or CI replication?
│   └── make test-ios SCHEME="<Module>" DEVICE="<Device>"
└── Specific class or method?
    ├── Xcode MCP available?
    │   └── XcodeOpenWorkspace → XcodeGrep (owner) → record state → XcodeSwitchScheme
    │       → XcodeSwitchRunDestination → GetTestList → RunSomeTests → restore
    └── No MCP?
        └── xcodebuild -only-testing
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Calling tools before approval | Call `XcodeOpenWorkspace` first — it triggers the approval prompt |
| Omitting `workspaceIdentifier` | Required in practice on every call except `XcodeListWorkspaces` / `XcodeOpenWorkspace` |
| Running a test outside the active scheme | `XcodeSwitchScheme` to the owning module first |
| Running iOS tests on `My Mac` | `XcodeSwitchRunDestination` to an iOS simulator |
| Using `"DatadogCore iOS"` style names | Schemes are `DatadogCore`; test targets are `DatadogCoreTests` |
| Reading only the inline `GetTestList` output | It's capped at 100 — grep `fullTestListPath` |
| Leaving Xcode on a different scheme | Switch back to the scheme/destination the user had |
