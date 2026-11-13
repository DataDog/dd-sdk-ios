---
name: dd-sdk-ios:build-settings
description: Use when inspecting or changing build settings, compiler flags, Swift flags, deployment targets, active compilation conditions, Info.plist keys, or entitlements for a dd-sdk-ios Xcode target. Use when you would otherwise read or edit project.pbxproj directly.
---

# dd-sdk-ios Build Settings

## Overview

Never read or edit `project.pbxproj` by hand for build settings. Use the Xcode MCP tools — but know where a setting comes from first: most shared settings live in **xcconfig files**, and the MCP tools only write **target-level** overrides.

## Setup (once per session)

```
XcodeOpenWorkspace(path: "<repo>/Datadog.xcworkspace")   # → workspaceIdentifier
```
If the agent isn't approved yet, this call makes Xcode prompt the user. Pass `workspaceIdentifier` to every other call — the schema says optional, calls fail without it; an absolute path is rejected despite the schema. The `mcp__xcode__*` tools are deferred — load them by exact name with `ToolSearch("select:mcp__xcode__<Tool>,...")`; a `+xcode` keyword search misses tools without "Xcode" in their name. Target names come from `XcodeListTargets` (e.g. `DatadogLogs`, `DatadogLogsTests`).

## Where Settings Live

| Layer | Location | How to change |
|-------|----------|---------------|
| Shared, all targets | `xcconfigs/Base.xcconfig` | `Edit` the xcconfig |
| Secrets / dev team | `xcconfigs/Datadog.xcconfig` | Don't add build settings here |
| Per-target xcconfig | `Datadog/TargetSupport/<Target>/<Target>.xcconfig` (e.g. `DatadogTests`, `Example`, `DatadogCrashReporting`) | `Edit` the xcconfig |
| Local developer overrides | `xcconfigs/*.local.xcconfig` (gitignored) | Don't touch |
| One target, no xcconfig | target build settings in pbxproj | `UpdateTargetBuildSetting` |

**Shared settings belong in the xcconfig.** Setting a target-level value with `UpdateTargetBuildSetting` silently overrides the xcconfig for that target only, and other modules drift.

## Quick Reference

| Goal | Tool |
|------|------|
| Read all settings of a target | `GetTargetBuildSettings(targetName:)` |
| Set / append / delete a target setting | `UpdateTargetBuildSetting` |
| Per-file compiler flags | `GetFileCompilerFlags` / `UpdateFileCompilerFlags` |
| Info.plist key | `AddInfoPlist` |
| Entitlement | `AddEntitlement` |

## Reading Settings

```
GetTargetBuildSettings(workspaceIdentifier: <id>, targetName: "DatadogLogs")
```
- Returns ~500 entries with no filter — scan for the `macroName` you need.
- `evaluatedValue` = final resolved value. `value` = the expression before resolution (e.g. `$(inherited) DD_SDK_COMPILED_FOR_TESTING`).
- `targetValue` is present **only** when the target itself sets it. No `targetValue` → it comes from the xcconfig or project defaults → change the xcconfig.

## Changing Settings

```
UpdateTargetBuildSetting(
  workspaceIdentifier: <id>,
  targetName: "DatadogLogs",
  buildSettingName: "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
  buildSettingValue: "MY_FLAG",
  appendValue: true
)
```
- Omit `buildSettingValue` to **delete** the target-level setting.
- Keep `"YES"` / `"NO"` as-is — never convert to `true` / `false`.
- Pass `projectPath` only if the same target name exists in several projects.

**Per-file compiler flags** are a last resort. For Swift files they are usually ignored (Swift compiles per module) — use `OTHER_SWIFT_FLAGS` at target level instead.

**Info.plist / entitlements:** changes only come up for the `Example` app. Use `AddInfoPlist` / `AddEntitlement` rather than editing the files.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Grepping / editing `project.pbxproj` | `GetTargetBuildSettings` / `UpdateTargetBuildSetting` |
| Changing a shared setting on one target | Edit `xcconfigs/Base.xcconfig` |
| Changing only `DatadogLogs` when all modules need it | Use the xcconfig, or update every module target |
| Per-file flags on a `.swift` file | Target-level `OTHER_SWIFT_FLAGS` |
