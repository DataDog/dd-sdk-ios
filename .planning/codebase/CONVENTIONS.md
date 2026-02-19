# Conventions — dd-sdk-ios

## Language & Toolchain

- **Language:** Swift 5.9+ (swift-tools-version: 5.9)
- **Platforms:** iOS 12+, tvOS 12+, macOS 12+, watchOS 7+
- **Dependency Managers:** SPM (primary), CocoaPods, Carthage
- **Linter:** SwiftLint with explicit `only_rules` configuration

## Code Style

### Enforced via SwiftLint (`tools/lint/sources.swiftlint.yml`)

Key enforced rules:
- `explicit_top_level_acl` — all top-level declarations must have explicit access control
- `force_cast`, `force_try`, `force_unwrapping` — forbidden in source code
- `implicitly_unwrapped_optional` — forbidden
- `unused_declaration`, `unused_import` — enforced
- `todo_without_jira` — all TODOs must reference JIRA (e.g., `TODO: RUM-123`)
- `unsafe_uiapplication_shared` — use `UIApplication.managedShared` instead
- `unsafe_all_http_header_fields` — use `URLRequest.value(forHTTPHeaderField:)` instead
- `required_reason_api_name` — symbol names must not conflict with Apple's Required Reason APIs
- `@ReadWriteLock` attribute must always be on line above

### Naming Conventions

- **Types:** `PascalCase` for classes, structs, enums, protocols
- **Functions/Properties:** `camelCase`
- **Protocols:** Named as capabilities or contracts (e.g., `DatadogCoreProtocol`, `FeatureScope`, `MessageBusReceiver`)
- **Internal types:** Prefixed with module context (e.g., `RUMCommand`, `RUMViewScope`)
- **Mock types:** Suffixed with `Mock` or `Spy` (e.g., `HTTPClientMock`, `SnapshotProcessorSpy`)
- **Test files:** Mirror source path with `Test__` or `Tests` suffix (e.g., `RUMViewScopeTests.swift`)

### File Organization

- **License header:** Required on all files (checked by `make license-check`)
  ```swift
  /*
   * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
   * This product includes software developed at Datadog (https://www.datadoghq.com/).
   * Copyright 2019-Present Datadog, Inc.
   */
  ```
- **MARK comments:** Used for section organization (e.g., `// MARK: - Initialization`)
- **Imports:** Module imports at top, `@testable import` only in test files

### Access Control

- **Public API:** Explicit `public` on all API-facing declarations
- **Internal:** Default access for implementation details
- **Private:** Used for truly encapsulated state
- **`@testable import`:** Only in test targets; never in production code
- **`#if !DD_COMPILED_FOR_INTEGRATION_TESTS`:** Conditional compilation for testability in integration test targets

## Architecture Patterns

### Module Structure

Each module follows a consistent layout:
```
Module/
  Sources/        # Production code
  Tests/          # Unit tests
  Resources/      # Privacy manifests, etc.
```

### Dependency Injection

- Constructor injection preferred
- Protocol-based abstractions for testability
- `DatadogCoreProtocol` as the central injectable core
- Mock implementations in `TestUtilities/` target

### Thread Safety

- **`@ReadWriteLock`:** Property wrapper for concurrent read, exclusive write access
- **Serial queues:** For scope processing in RUM (e.g., `RUMScopeQueue`)
- **No `DispatchQueue.main.sync`:** Avoided to prevent deadlocks
- **Atomic operations:** Via lock wrappers, never raw locking primitives

### Error Handling

- **Never crash:** SDK code must never crash (ZEN.md philosophy)
- **`DD.logger`:** Internal logger for SDK errors/warnings (not customer-facing)
- **`InternalLogger`:** Used for telemetry about SDK health
- **Graceful degradation:** On error, log and continue — do not throw to the customer
- **`consolePrint()`:** Used instead of `print()` for debug output

### Event Flow Pattern

1. Public API call → validate inputs
2. Create internal command/event (with UUID, timestamp)
3. Dispatch through scope hierarchy (Application → Session → View)
4. Scope processes event, may produce output events
5. Output events serialized to JSON via `Codable`
6. Written to file storage, batched for upload

### Configuration Pattern

- Builder or struct-based configuration (e.g., `RUM.Configuration`)
- Defaults follow cross-SDK parity
- `@available` markers for preview/experimental APIs
- Feature flags via `FeatureFlags` struct

## API Design Conventions

- **Minimal API surface:** Start small, extend slowly
- **Cross-SDK consistency:** API names and behaviors match other Datadog SDKs
- **Objective-C compatibility:** Key APIs bridged via `@objc` annotations
- **API surface tracking:** `make api-surface` generates/verifies public API files to catch unintended changes
- **Preview APIs:** Marked with `@available(*, message: "This API is in preview...")`

## Module Dependencies

```
DatadogInternal (shared types, protocols)
    ├── DatadogCore (initialization, storage, upload)
    │     ├── DatadogLogs
    │     ├── DatadogTrace
    │     ├── DatadogRUM
    │     ├── DatadogSessionReplay
    │     ├── DatadogCrashReporting
    │     ├── DatadogWebViewTracking
    │     ├── DatadogFlags
    │     └── DatadogProfiling
    └── TestUtilities (test-only, shared mocks/matchers)
```

All feature modules depend on `DatadogInternal` for shared protocols and types. Only `DatadogCore` provides the concrete implementation.

## Conditional Compilation

- `SPM_BUILD` — defined when building via Swift Package Manager
- `DD_BENCHMARK` — defined for benchmark builds
- `DD_COMPILED_FOR_INTEGRATION_TESTS` — used to toggle `@testable` imports
- Platform checks: `#if os(iOS)`, `#if canImport(UIKit)`, etc.
