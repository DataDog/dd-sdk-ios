---
name: dd-sdk-ios:xcode-file-management
description: Use when adding, removing, moving, copying, renaming, or editing Swift source files in the dd-sdk-ios Xcode project. Use when the task involves file creation, deletion, or relocation in any module (DatadogRUM, DatadogLogs, DatadogCore, etc.). Use when you would otherwise reach for Write, Bash mv/mkdir/rm, or manual pbxproj editing for file management.
---

# dd-sdk-ios Xcode File Management

## Overview

The dd-sdk-ios project is both an SPM package **and** an Xcode workspace with `.pbxproj` files. SPM builds discover files automatically, but **Xcode does not** — it requires explicit registration in `.pbxproj`. The Xcode MCP server handles this automatically. Always use it.

## Prerequisites

Requires **Xcode 27** with the Xcode MCP server connected. If the `mcp__xcode__*` tools are missing, stop and ask the user to enable "Allow external agents to use Xcode tools" in Xcode Intelligence settings and reconnect with `/mcp`.

**Get a workspaceIdentifier (once per session):**
```
XcodeOpenWorkspace(path: "<repo>/Datadog.xcworkspace")
# → workspaceIdentifier e.g. "workspace-sMg5URZMpB"
```
- If the agent isn't approved yet, this call makes Xcode prompt the user. Until then, every tool fails with *"This agent isn't approved to use Xcode's tools yet"*.
- If the workspace is already open, `XcodeListWorkspaces()` returns its identifier.
- **Pass `workspaceIdentifier` to every other call.** The schema marks it optional, but calls fail without it. Despite the schema, an absolute path is rejected — use the returned identifier.
- The `mcp__xcode__*` tools are deferred — load them by exact name with `ToolSearch("select:mcp__xcode__<Tool>,...")`; a `+xcode` keyword search misses tools without "Xcode" in their name.

## The Rule

**Never use `Write`, `Bash mv/mkdir/rm`, or `Edit` for file creation, deletion, or movement in this project.**

Use Xcode MCP tools instead — they update the filesystem AND the `.pbxproj` in one atomic operation.

## Target Membership

Target membership is **implicit** — Xcode MCP infers the target from the navigator path where the file is placed. A file added under `Datadog/DatadogLogs/` is automatically assigned to the `DatadogLogs` target. No explicit target specification is needed.

## Quick Reference

| Operation | Use This Tool | Never Use |
|-----------|--------------|-----------|
| Create file | `XcodeWrite` | `Write`, `Bash touch/cat` |
| Delete file | `XcodeRM` | `Bash rm` |
| Move / rename | `XcodeMV` | `Bash mv` |
| Copy | `XcodeMV(operation: "copy")` | `Bash cp` |
| Create directory/group | `XcodeMakeDir` | `Bash mkdir` |
| Edit existing file | `XcodeUpdate` | (either is fine — `Edit` doesn't touch pbxproj) |
| Read file | `XcodeRead` | (either is fine) |
| Search files | `XcodeGlob`, `XcodeGrep`, `XcodeLS` | (either is fine) |

`XcodeRM` moves the file to the Trash by default (`deleteFiles: true`). Pass `deleteFiles: false` to only remove the project reference. Directories need `recursive: true`.

## Common Rationalizations — All Wrong

| Excuse | Reality |
|--------|---------|
| "SPM auto-discovers files, pbxproj doesn't matter" | The Xcode workspace has `.pbxproj` files. They must stay in sync or Xcode breaks. |
| "It's faster to use bash" | A file invisible to Xcode causes build failures and confuses teammates. |
| "I'll update pbxproj manually after" | pbxproj is binary-adjacent XML; manual edits cause merge conflicts and corruption. |
| "The file is just temporary" | Temporary files still break the build if Xcode can't see them. |

## Path Format

Xcode MCP uses **project navigator paths**, not filesystem paths. Use `XcodeLS` to discover them:

```
XcodeLS(workspaceIdentifier: <id>, path: "Datadog/DatadogLogs", recursive: false)
# → ["ConsoleLogger.swift", "Logger.swift", "Feature/", "Log/", "Scrubbing/", ...]
```

Navigator paths start with the `Datadog` project group, and module groups skip the `Sources/` folder:

| On disk | Navigator path |
|---------|----------------|
| `DatadogLogs/Sources/Foo.swift` | `Datadog/DatadogLogs/Foo.swift` |
| `DatadogInternal/Sources/Utils/DateFormatting.swift` | `Datadog/DatadogInternal/Utils/DateFormatting.swift` |

When unsure, find the file with `XcodeGlob(workspaceIdentifier: <id>, pattern: "**/DateFormatting.swift")`. Some tools accept a path without the `Datadog/` prefix, but `XcodeGlob` doesn't — always use the full form.

## Example

```
# ✅ Add a new source file
XcodeWrite(
  workspaceIdentifier: <id>,
  filePath: "Datadog/DatadogLogs/Feature/LogBatcher.swift",
  content: "..."
)
# → Creates file on disk AND registers it in pbxproj + target membership

# ✅ Move a file
XcodeMV(
  workspaceIdentifier: <id>,
  sourcePath: "Datadog/DatadogLogs/Feature/LogBatcher.swift",
  destinationPath: "Datadog/DatadogLogs/Log/LogBatcher.swift"
)
# → Moves file on disk AND updates pbxproj reference

# ❌ Wrong — file created on disk but invisible to Xcode
Write(file_path: ".../DatadogLogs/Sources/LogBatcher.swift", content: "...")
```

## After File Operations

Check the edited file, then verify the module still builds:

```
XcodeRefreshCodeIssuesInFile(workspaceIdentifier: <id>, filePath: "Datadog/DatadogLogs/Feature/LogBatcher.swift")
BuildProject(workspaceIdentifier: <id>)
GetBuildLog(workspaceIdentifier: <id>, severity: "error")   # if the build failed
```

`BuildProject` builds the **active scheme** — switch to the module you touched first (see the `dd-sdk-ios:build-and-diagnose` skill).
