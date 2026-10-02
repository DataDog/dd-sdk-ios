---
name: dd-sdk-ios:build-and-diagnose
description: Use when building dd-sdk-ios, reading build errors, warnings, or compiler diagnostics, or running a Swift snippet against SDK code to check behavior. Use after editing Swift files to check they compile, or when fixing compiler errors before running tests.
---

# Building and Diagnosing dd-sdk-ios

## Overview

The Xcode MCP server builds the active scheme, returns structured build logs, and runs Swift snippets inside a module's context. Prefer it over `xcodebuild` output parsing.

## Setup (once per session)

```
XcodeOpenWorkspace(path: "<repo>/Datadog.xcworkspace")   # → workspaceIdentifier
```
- If the agent isn't approved yet, this call makes Xcode prompt the user; until then every tool fails with *"This agent isn't approved to use Xcode's tools yet"*.
- If already open, `XcodeListWorkspaces()` returns the identifier.
- **Pass `workspaceIdentifier` to every other call** — the schema says optional, calls fail without it. Despite the schema, an absolute path is rejected — use the returned identifier.
- The `mcp__xcode__*` tools are deferred — load them by exact name with `ToolSearch("select:mcp__xcode__<Tool>,...")`; a `+xcode` keyword search misses tools without "Xcode" in their name.

## Quick Reference

| Goal | Tool |
|------|------|
| Build active scheme | `BuildProject` (`buildForTesting: true` to include test targets) |
| Read build errors | `GetBuildLog` (default `severity: "error"`) |
| Diagnostics for one file | `XcodeRefreshCodeIssuesInFile(filePath:)` |
| Pick which module builds | `XcodeListSchemes` → `XcodeSwitchScheme` |
| Pick platform | `XcodeListRunDestinations` → `XcodeSwitchRunDestination` |
| Run Swift in a module's context | `RunCodeSnippet` |

## Build-and-Fix Loop

1. **Select the module.** `BuildProject` builds the **active scheme** only. Schemes are named after modules (`DatadogLogs`, `DatadogRUM`, …).
   ```
   XcodeSwitchScheme(workspaceIdentifier: <id>, schemeName: "DatadogLogs")
   ```
   Schemes are multiplatform — the destination may be `My Mac`. Switch to an iOS simulator when the code is iOS-only (UIKit, `#if os(iOS)`).
2. **Build.**
   ```
   BuildProject(workspaceIdentifier: <id>)
   ```
3. **Read errors.**
   ```
   GetBuildLog(workspaceIdentifier: <id>, severity: "error")
   GetBuildLog(workspaceIdentifier: <id>, severity: "warning", pattern: "Sendable")
   ```
   - The project has many existing warnings (Swift 6 Sendable, deprecations). At `warning` severity, narrow with `pattern` (regex on message), or the output is huge.
   - Avoid `glob` for narrowing: it also matches build-task locations, so `glob: "**/DatadogLogs/**"` returns every compile task in that folder — issue-free ones included — and truncates at 100.
   - `GetBuildLog` reads the **most recent** build. `RunCodeSnippet`, `RunSomeTests`, and `RunProject` all build too and replace it — read the log right after `BuildProject`.
   - Full log is at `fullLogPath`.
4. **Fix, then check the file** without a full rebuild:
   ```
   XcodeRefreshCodeIssuesInFile(workspaceIdentifier: <id>, filePath: "Datadog/DatadogLogs/Logger.swift")
   ```
5. **Repeat** until `GetBuildLog` reports `"The build succeeded"`, then run tests (`dd-sdk-ios:running-tests`).
6. **Restore** the scheme/destination the user had (from the `XcodeOpenWorkspace` response).

File paths are project navigator paths (`Datadog/<Module>/...`) — see `dd-sdk-ios:xcode-file-management`.

## Running Swift Snippets

`RunCodeSnippet` builds and runs code in the context of a source file — it sees that module's `internal` and the file's `fileprivate` declarations. Output is whatever the snippet `print`s.

```
RunCodeSnippet(
  workspaceIdentifier: <id>,
  sourceFilePath: "Datadog/DatadogInternal/Utils/DateFormatting.swift",
  purpose: "Check ISO8601 formatter output",
  codeSnippet: "print(iso8601DateFormatter.string(from: Date(timeIntervalSince1970: 0)))"
)
# → "1970-01-01T00:00:00.000Z"
```
- `purpose` must not contain the word "test".
- Only works for files in framework/app/library targets — not test targets.
- Use it to probe behavior quickly; it doesn't replace a unit test.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Building after editing `DatadogRUM` while `DatadogCore` is active | `XcodeSwitchScheme` to the edited module first |
| `GetBuildLog(severity: "warning")` with no filter | Add `pattern` — existing warnings flood the output |
| Reading the build log after running a snippet or tests | Those replaced it — rerun `BuildProject` first |
| Rebuilding to check one file | `XcodeRefreshCodeIssuesInFile` |
| Parsing `xcodebuild` output by hand | Use `GetBuildLog` structured entries |
| Using the word "test" in `RunCodeSnippet.purpose` | Describe what it checks instead |
