---
name: dd-sdk-ios:debug
description: Use when running the dd-sdk-ios Example app, reading its console or OSLog output, or debugging SDK behavior at runtime with lldb — breakpoints, backtraces, inspecting variables, crashes, hangs, or unexpected stops in a running app.
---

# Debugging dd-sdk-ios at Runtime

## Overview

The Xcode MCP server can build and launch a scheme, attach lldb, send debugger commands, and read console output. The SDK is a set of frameworks — to see it run, launch the **`Example`** app scheme.

## Setup (once per session)

```
XcodeOpenWorkspace(path: "<repo>/Datadog.xcworkspace")   # → workspaceIdentifier, activeScheme, activeRunDestination
```
If the agent isn't approved yet, this call makes Xcode prompt the user. Pass `workspaceIdentifier` to every other call — the schema says optional, calls fail without it; an absolute path is rejected despite the schema. The `mcp__xcode__*` tools are deferred — load them by exact name with `ToolSearch("select:mcp__xcode__<Tool>,...")`; a `+xcode` keyword search misses tools without "Xcode" in their name. **Note the original scheme and destination** so you can restore them.

## Quick Reference

| Goal | Tool |
|------|------|
| Pick the app | `XcodeSwitchScheme(schemeName: "Example")` |
| Pick simulator | `XcodeListRunDestinations` → `XcodeSwitchRunDestination(displayTitle:)` |
| Build + launch | `RunProject(attachDebugger: true)` |
| lldb command | `InvokeDebuggerCommand(command:)` |
| Console / OSLog | `GetConsoleOutput` |
| Stop | `StopProject` |

## Workflow

1. **Select app and simulator.**
   ```
   XcodeSwitchScheme(workspaceIdentifier: <id>, schemeName: "Example")
   XcodeSwitchRunDestination(workspaceIdentifier: <id>, displayTitle: "iPhone 17 Pro (27.0)")
   ```
2. **Set breakpoints before launch if needed** — or launch, then set them (lldb shares state with Xcode's UI).
3. **Launch.**
   ```
   RunProject(workspaceIdentifier: <id>, attachDebugger: true)
   # → runResult, processIdentifier, launchSessionReference, buildErrors
   ```
   Without `attachDebugger: true`, `InvokeDebuggerCommand` has no session. Build errors come back in `buildErrors` — see `dd-sdk-ios:build-and-diagnose`.
4. **Check state first.** Always start with:
   ```
   InvokeDebuggerCommand(workspaceIdentifier: <id>, command: "process status")
   ```
   If stopped, find out why before anything else:
   ```
   InvokeDebuggerCommand(workspaceIdentifier: <id>, command: "thread backtrace -c 10")
   ```
   A stop with `EXC_BREAKPOINT` inside UIKitCore/SwiftUI is usually a **runtime issue trap**, not your breakpoint — read the frame names.
5. **Debug.** Any lldb command works: `breakpoint set -n <symbol>`, `frame variable`, `po <expr>`, `thread step-over`. Expressions need a stopped process. For `continue`, raise `timeout` (default 30s).
6. **Read output.**
   ```
   GetConsoleOutput(workspaceIdentifier: <id>, pattern: "DATADOG SDK", contextLines: 2)
   GetConsoleOutput(workspaceIdentifier: <id>, outputType: "oslog", oslogSeverity: ["error", "fault"])
   ```
   Default is the last 500 lines of the current launch; narrow with `pattern`, `outputType`, `tailLimit`. SDK debug logs appear only if the app sets `Datadog.verbosityLevel`.
7. **Stop and restore.**
   ```
   StopProject(workspaceIdentifier: <id>)
   XcodeSwitchScheme(workspaceIdentifier: <id>, schemeName: <original>)
   XcodeSwitchRunDestination(workspaceIdentifier: <id>, displayTitle: <original>)
   ```
   Switch the scheme **before** the destination — the scheme switch carries the current destination over.

`RunProject` replaces the "most recent build" that `GetBuildLog` reads.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running a framework scheme (`DatadogLogs`) | Only app schemes launch — use `Example` |
| `RunProject` without `attachDebugger: true` | No lldb session — stop and relaunch with it |
| `po` while the process is running | `process status` first; interrupt or hit a breakpoint |
| Assuming a stop is your breakpoint | `thread backtrace` — it may be a system runtime-issue trap |
| Leaving the app running / Xcode on `Example` | `StopProject`, then restore scheme, then destination |
