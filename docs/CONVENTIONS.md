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
- `unsafe_uiapplication_shared` — use `UIApplication.managedShared` instead
- `required_reason_api_name` — symbol names must not conflict with Apple's Required Reason APIs

Config: `tools/lint/sources.swiftlint.yml` (sources), `tools/lint/tests.swiftlint.yml` (tests)

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
