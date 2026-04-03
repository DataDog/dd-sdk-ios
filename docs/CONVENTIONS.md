# Coding Conventions

## Naming Conventions

**Types:** `PascalCase` for classes, structs, enums, protocols
**Functions/Properties:** `camelCase`
**Protocols:** Named as capabilities or contracts (e.g., `DatadogCoreProtocol`, `FeatureScope`, `MessageBusReceiver`)
**Internal types:** Prefixed with module context (e.g., `RUMCommand`, `RUMViewScope`)
**Mock types:** Suffixed with `Mock` or `Spy` (e.g., `HTTPClientMock`, `SnapshotProcessorSpy`)
**Test files:** Mirror source path with `Tests` suffix (e.g., `RUMViewScopeTests.swift`)

**File naming patterns:**
- Feature entry point: `{Feature}.swift` (e.g., `RUM.swift`, `Logs.swift`)
- Feature configuration: `{Feature}Configuration.swift`
- Feature plugin: `Feature/{Feature}Feature.swift`
- Scope files: `RUM{ScopeName}Scope.swift`

## SwiftLint Rules (sources)

- `explicit_top_level_acl` — all top-level declarations must have explicit access control
- `force_cast`, `force_try`, `force_unwrapping` — forbidden in source code
- `todo_without_jira` — all TODOs must reference JIRA (e.g., `TODO: RUM-123`)
- `unsafe_uiapplication_shared` — see [UIApplication Access](#uiapplication-access) below
- `required_reason_api_name` — see [Required Reason API Names](#required-reason-api-names) below

Config: `tools/lint/sources.swiftlint.yml` (sources), `tools/lint/tests.swiftlint.yml` (tests)

### UIApplication Access

`UIApplication.shared` is **forbidden** in source code (lint severity: `error`). Apple marks it `@available(iOSApplicationExtension, unavailable)` — calling it in an app extension target is a compiler error. Since the SDK can be linked into both apps and extensions, all code must use the safe alternative:

```swift
// WRONG — lint error, compiler error in extensions
let app = UIApplication.shared

// CORRECT — returns nil in extension context, safe everywhere
let app = UIApplication.dd.managedShared
```

`UIApplication.dd.managedShared` (defined in `DatadogInternal/Sources/Utils/UIKitExtensions.swift`) uses KVC (`value(forKeyPath:)`) to bypass the compiler restriction. It returns `UIApplication?` — `nil` in app extension context, the shared instance in a full app.

This restriction applies only to `UIApplication.shared`. `UIDevice.current` is safe in extensions and has no lint rule.

### Required Reason API Names

The `required_reason_api_name` rule (severity: `error`) bans declaring symbols whose names match Apple's Required Reason APIs. This prevents third-party static analysis tools from flagging false positives on SDK consumers.

**You cannot use these as property, variable, or function names** (even if your code has nothing to do with the restricted API):

| Category | Banned names |
|----------|-------------|
| File timestamps | `.creationDate`, `.modificationDate`, `.fileModificationDate`, `.creationDateKey`, `.contentModificationDateKey` |
| System uptime | `systemUptime`, `mach_absolute_time()` |
| Disk space | `volumeAvailableCapacityKey`, `volumeTotalCapacityKey`, `systemFreeSize`, `systemSize` |
| User defaults | `UserDefaults`, `NSUserDefaults`, `AppStorage` |
| Keyboards | `activeInputModes` |

These names are allowed in comments, doc comments, and string literals — only actual code references are blocked. Full list: `tools/lint/sources.swiftlint.yml` lines 101-155.

Do not disable lint rules except where the rule is incorrect and a Jira ticket exists to track reinstating it.

## Conditional Compilation

- `SPM_BUILD` — defined when building via Swift Package Manager
- `DD_BENCHMARK` — defined for benchmark builds
- `DD_COMPILED_FOR_INTEGRATION_TESTS` — toggles `@testable` imports for integration tests
- Platform checks: `#if os(iOS)`, `#if canImport(UIKit)`, `#if os(tvOS)`

## Generated Models — DO NOT EDIT

Files in `DatadogInternal/Sources/Models/` are auto-generated from the [rum-events-format](https://github.com/DataDog/rum-events-format) schema. Never hand-edit. Regenerate with `make rum-models-generate GIT_REF=master`, verify with `make rum-models-verify`.

## File Headers

All source files must include the Apache License header:
```swift
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
```

## Commit & PR Conventions

### Commit Requirements
- **All commits MUST be signed** (GPG or SSH signature)
- **Prefix**: `[PROJECT-XXXX]` where PROJECT is the JIRA Project shortname (RUM, FFL, ...) and XXXX is the JIRA ticket number. It applies only for internal development. Third party contributions do not need it.
- Example: `[RUM-1234] Add baggage header merging support`, `[FFL-213] Add Feature Flags support`

### PR Requirements
- **Always follow `.github/PULL_REQUEST_TEMPLATE.md`** when creating PRs
- **Title prefix**: `[PROJECT-XXXX]` matching the JIRA ticket
- Include thorough test coverage
- Pass all CI checks (lint, tests, API surface verification)
