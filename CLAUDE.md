# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Guidelines

**ALWAYS adhere to AGENTS.md at all times.** This file contains comprehensive development patterns, conventions, and best practices for the Datadog iOS SDK project.

## Overview

This is the Datadog SDK for iOS and tvOS - a modular Swift/Objective-C library for observability (Logs, Traces, RUM, Session Replay, Crash Reporting, WebView Tracking, and Feature Flags).

## Build & Test Commands

### Initial Setup
```bash
make                         # Setup repo, install dependencies, and templates
make repo-setup ENV=dev      # Setup repo for specific environment (dev/ci)
make dependencies            # Bootstrap Carthage dependencies
```

### Testing
```bash
# Unit Tests
make test-ios SCHEME="DatadogCore iOS"           # Run specific iOS scheme
make test-ios-all                                 # Run all iOS unit tests
make test-tvos SCHEME="DatadogCore tvOS"         # Run specific tvOS scheme
make test-tvos-all                                # Run all tvOS unit tests

# Run single test (use Xcode directly or xcodebuild)
xcodebuild test -workspace Datadog.xcworkspace -scheme "DatadogCore iOS" -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:DatadogCoreTests/SpecificTestClass/testMethod

# UI Tests
make ui-test TEST_PLAN="Default"                 # Run specific UI test plan
make ui-test-all                                  # Run all UI test plans
make ui-test-podinstall                           # Update UI test project dependencies

# Session Replay Snapshot Tests
make sr-snapshot-test                             # Run SR snapshot tests
make sr-snapshots-pull                            # Pull reference snapshots from repo
make sr-snapshots-push                            # Push updated snapshots to repo
make sr-snapshot-tests-open                       # Open SR snapshot tests project

# Smoke Tests
make smoke-test-ios-all                           # Run all iOS smoke tests (SPM, Carthage, CocoaPods, XCFrameworks)
make smoke-test-tvos-all                          # Run all tvOS smoke tests

# Tools Tests
make tools-test                                   # Run tests for repo tools
```

### Building
```bash
# SPM Builds
make spm-build-ios                                # Build for iOS
make spm-build-tvos                               # Build for tvOS
make spm-build-visionos                           # Build for visionOS
make spm-build-watchos                            # Build for watchOS (subset of modules)
make spm-build-macos                              # Build for macOS/Catalyst

# Benchmark
make benchmark-build                              # Build benchmark app
```

### Code Quality
```bash
make lint                                         # Run SwiftLint
./tools/lint/run-linter.sh --fix                 # Apply automatic linter fixes
make license-check                                # Check license headers
make api-surface                                  # Generate API surface files
make api-surface-verify                           # Verify API surface hasn't changed
```

### Model Generation
```bash
make rum-models-generate GIT_REF=master          # Generate RUM data models
make rum-models-verify                            # Verify RUM models match schemas
make sr-models-generate GIT_REF=master           # Generate Session Replay models
make sr-models-verify                             # Verify SR models match schemas
```

### Cleanup
```bash
make clean                                        # Clean derived data, pods, xcconfigs
make clean-carthage                               # Clean Carthage build artifacts
```

## Architecture

### Module Structure

The SDK is organized into independent, modular targets:

- **DatadogInternal**: Internal shared utilities, protocols, and models used across all modules. Contains core infrastructure like context providers, message bus, network instrumentation base, telemetry, and storage protocols.

- **DatadogCore**: The main SDK module providing initialization, configuration, context management, data storage/upload, and the message bus for inter-module communication.
- **DatadogLogs**: Logs collection feature
- **DatadogTrace**: APM trace collection with OpenTelemetry API support
- **DatadogRUM**: Real User Monitoring (RUM) events collection
- **DatadogSessionReplay**: Session Replay recording and processing
- **DatadogCrashReporting**: Crash reporting using PLCrashReporter
- **DatadogWebViewTracking**: Web view tracking integration
- **DatadogFlags**: Feature flags support

- **TestUtilities**: Shared testing utilities and mocks (not exported by default)

### Core Architecture Patterns

**Initialization Flow**: SDK is initialized via `Datadog.initialize(with:trackingConsent:)` which creates a `DatadogCore` instance. Individual features are then enabled (e.g., `Logs.enable()`, `RUM.enable()`, `Trace.enable()`). Each feature registers with the core instance. When not initialized, the SDK uses NOP (no-op) implementations (`NOPMonitor`, `NOPDatadogCore`) that silently accept all API calls.

**Message Bus**: Inter-module communication happens through a message bus (`MessageBusReceiver`). Features can subscribe to receive messages from other features (e.g., RUM subscribes to crash events, Session Replay subscribes to RUM view updates). The bus is the only way features communicate — they must NOT import each other.

**Context Propagation**: `DatadogContext` is the central context object containing device info, app state, user info, network state, etc. It is built by `DatadogContextProvider` from multiple `ContextValuePublisher` instances that subscribe to system notifications and update context in real-time. Context flows through the SDK and is attached to telemetry events.

**Storage & Upload**: Each feature writes events to disk using a storage layer, then an upload worker batches and sends data to Datadog backend. Upload uses a backoff strategy and respects battery/network conditions.

**Dependency Injection**: The SDK heavily uses dependency injection for testability. Production implementations are in `DatadogCore/Sources/Core`, test utilities in `TestUtilities`.

**Thread Safety**: Most SDK operations use background queues. Thread-safe access is managed via `@ReadWriteLock` property wrapper or dedicated serial queues. No `DispatchQueue.main.sync` — deadlock risk.

### Storage

- **File-based storage** in Application Support sandbox — no database (SQLite/CoreData)
- **Directory structure**: `[AppSupport]/Datadog/[site]/[feature]/`
- **Format**: JSON for events, binary TLV encoding for compact storage
- **Encryption**: Optional via `DataEncryption` protocol implementation
- **Caching**: Explicitly disabled at URLSession level (ephemeral config, `urlCache = nil`)
- **Key-value storage**: `FeatureDataStore` for feature-specific persistent data

### OpenTelemetry Integration

The SDK can be compiled against either:
- Lightweight OpenTelemetry API mirror (default): https://github.com/DataDog/opentelemetry-swift-packages
- Full OpenTelemetry SDK: Set `OTEL_SWIFT` environment variable before building

### Platform Support

- iOS: v12+ (v13+ when using full OTEL_SWIFT mode)
- tvOS: v12+ (v13+ when using full OTEL_SWIFT mode)
- watchOS: v7+ (subset of modules: DatadogCore, DatadogLogs, DatadogTrace)
- macOS: v12+ (subset of modules + full Catalyst support)
- visionOS: supported for most modules

## Development Philosophy (from ZEN.md)

**Zero Crashes**: SDK code must never crash unless it's a top-level developer mistake with a clear error message. Prefer logging errors and gracefully degrading functionality.

**Small Footprint**: Minimize runtime performance impact, library size, and network load. Heavy work should be delegated to background threads.

**Stability**: Avoid major breaking changes. Updates should be transparent except for major version bumps.

**Code Architecture**: Favor Object-Oriented design following SOLID principles. All code must be tested and reviewed.

**API Design**: Start small, extend slowly. Keep APIs consistent with previous versions, other Datadog products, and iOS community best practices.

## Testing Strategy

- **Unit Tests**: Located in `<Module>/Tests/`. Each module has comprehensive unit tests using mocks from `TestUtilities`.
- **Integration Tests**: Located in `IntegrationTests/`. UI-based integration tests using CocoaPods. Run with `make ui-test` or `make ui-test-all`.
- **E2E Tests**: Located in `E2ETests/`. Synthetic tests that run daily against real Datadog backend to verify end-to-end data flow.
- **Smoke Tests**: Located in `SmokeTests/`. Test SDK integration with different dependency managers (SPM, CocoaPods, Carthage, XCFrameworks).
- **Snapshot Tests**: Session Replay has visual snapshot tests (`DatadogSessionReplay/SRSnapshotTests/`) to catch UI rendering regressions.
- **Benchmark Tests**: Located in `BenchmarkTests/`. Measure SDK performance impact.

## Tools

- **api-surface**: Generates and verifies public API surfaces for Swift and Objective-C to catch unintended API changes
- **rum-models-generator**: Python tool to generate RUM and Session Replay data model code from https://github.com/DataDog/rum-events-format
- **http-server-mock**: Mock HTTP server for integration testing
- **sr-snapshots**: Tool for managing Session Replay snapshot images
- **issue_handler**: Python tool for automated issue triage and analysis
- **lint**: SwiftLint wrapper with custom rules
- **license**: License header validation
- **release**: Release automation scripts
- **dogfooding**: Scripts to create dogfooding PRs in internal apps

## Module Dependencies

```
DatadogInternal (shared types, protocols — Foundation only, no external deps)
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

All feature modules depend on `DatadogInternal` for shared protocols and types. Only `DatadogCore` provides the concrete implementations. Feature modules MUST NOT import each other.

## HTTP Upload Details

- **Auth**: Client token passed as `DD-API-KEY` header on all requests
- **Custom headers**: `DD-EVP-ORIGIN` (SDK identifier), `DD-EVP-ORIGIN-VERSION` (SDK version), `DD-REQUEST-ID` (optional UUID)
- **Formats**: JSON, NDJSON (newline-delimited) for batches, multipart/form-data for SR/crashes
- **Compression**: Gzip (`Content-Encoding: gzip`)
- **Endpoints by site**: `.us1` → `browser-intake-datadoghq.com`, `.eu1` → `browser-intake-datadoghq.eu`, etc.
- **Header building**: `DatadogInternal/Sources/Upload/URLRequestBuilder.swift`

## Key SwiftLint Rules (sources)

- `explicit_top_level_acl` — all top-level declarations must have explicit access control
- `force_cast`, `force_try`, `force_unwrapping` — forbidden in source code
- `todo_without_jira` — all TODOs must reference JIRA (e.g., `TODO: RUM-123`)
- `unsafe_uiapplication_shared` — use `UIApplication.managedShared` instead
- `required_reason_api_name` — symbol names must not conflict with Apple's Required Reason APIs

Config: `tools/lint/sources.swiftlint.yml` (sources), `tools/lint/tests.swiftlint.yml` (tests — more permissive)

## Common Workflows

### Adding a New Feature to an Existing Module

1. Read the module's source code to understand existing patterns
2. Add implementation in `<Module>/Sources/`
3. Add comprehensive unit tests in `<Module>/Tests/`
4. Ensure all file creation, removal, move are reflected in corresponding pbxproj files when needed 
5. Update API surface: `make api-surface`
6. Run linter: `make lint`
7. Run tests: `make test-ios SCHEME="<Module> iOS"`

### Modifying RUM or Session Replay Data Models

1. Update schema in https://github.com/DataDog/rum-events-format (separate repo)
2. Regenerate models: `make rum-models-generate` or `make sr-models-generate`
3. Verify models: `make rum-models-verify` or `make sr-models-verify`
4. Update any breaking usages in the codebase

### Debugging UI Integration Tests

1. Install dependencies: `make ui-test-podinstall`
2. Open `IntegrationTests/IntegrationTests.xcworkspace` in Xcode
3. Run specific test from Xcode test navigator

### Working with Session Replay Snapshots

1. Pull latest reference snapshots: `make sr-snapshots-pull`
2. Run snapshot tests: `make sr-snapshot-test`
3. If snapshots change intentionally, review diffs and push: `make sr-snapshots-push`

### Adding a New RUM Command

1. Define a new struct in `DatadogRUM/Sources/RUMMonitor/RUMCommand.swift` conforming to `RUMCommand`
2. Include timestamp, attributes, and any decision hints (e.g., `canStartBackgroundView`)
3. Add public API method to `RUMMonitorProtocol.swift` and implement in `Monitor.swift`
4. Add processing logic in the appropriate scope (`RUMSessionScope`, `RUMViewScope`, etc.)
5. Add unit tests in `DatadogRUM/Tests/RUMTests/Scopes/`
6. Update API surface: `make api-surface`

### Adding a New Context Provider

1. Create `DatadogCore/Sources/Core/Context/<ProviderName>Publisher.swift`
2. Implement `ContextValuePublisher` protocol from `DatadogInternal`
3. Subscribe to relevant system notifications
4. Register the publisher in `DatadogContextProvider` initialization
5. Add the new value to `DatadogContext` if needed (in `DatadogInternal/Sources/Context/`)
6. Add unit tests in `DatadogCore/Tests/`

## CI Environment

The `ENV=ci` flag is used in CI to enable special behaviors (e.g., different API surface output paths). When debugging CI failures locally, you may need to set this.

## Documentation

- Official docs: https://docs.datadoghq.com/real_user_monitoring/ios
- SDK performance guidelines: `docs/sdk_performance.md`
- Session Replay performance: `docs/session_replay_performance.md`

## Contributing

- All commits must be signed (GPG/SSH signatures required)
- Keep PRs small and atomic, solving one issue each
- **Always follow `.github/PULL_REQUEST_TEMPLATE.md`** when creating PRs
- Code must pass `make lint`, `make test-ios-all`, `make test-tvos-all`, and API surface checks
- Follow patterns established in the codebase (OOP, SOLID principles, dependency injection)

## Claude additional Agent documentation

Claude can look at the `AGENTS.md` to gather more information about the project. Key modules also have localized `AGENTS.md` files:

- `DatadogRUM/AGENTS.md` — Scope hierarchy, RUMCommand patterns, instrumentation, known fragile areas
- `DatadogCore/AGENTS.md` — Core orchestrator, storage pipeline, context providers, MessageBus
- `DatadogInternal/AGENTS.md` — Shared protocols, generated models, context types
- `TestUtilities/AGENTS.md` — Mock protocols, test proxies, event matchers