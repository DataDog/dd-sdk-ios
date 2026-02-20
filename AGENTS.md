# AI Agents Guide for dd-sdk-ios

> This document outlines the rules, constraints, and expectations for AI agents contributing to the Datadog iOS SDK. Because the SDK powers mission-critical telemetry for thousands of customer applications, all changes must preserve stability, compatibility, and performance. Agents must strictly follow the guidelines below when navigating the repository, modifying code, or generating pull requests.

## Project Overview

The SDK is responsible for reliably collecting, batching, and transmitting telemetry from customer apps under strict performance, safety, and compliance constraints.

This is the **Datadog SDK for iOS and tvOS** - Swift and Objective-C libraries to interact with Datadog. The SDK enables:
- **Logs**: Send logs to Datadog
- **Traces**: OpenTelemetry-compatible tracer for sending traces (including distributed tracing)
- **RUM**: Real User Monitoring events collection
- **Session Replay**: Visual session recording
- **Crash Reporting**: Crash detection and reporting
- **WebView Tracking**: Hybrid app monitoring
- **Feature Flags**: Feature flag integration

## Related Documentation

Before starting work, familiarize yourself with these key documents:

- **`docs/LLM_FEATURE_DOCS_GUIDELINES.md`** - Guidelines for creating and updating `*_FEATURE.md` files
- **`ZEN.md`** - Core SDK philosophy and principles
- **`CONTRIBUTING.md`** - General contribution guidelines
- **Feature-specific docs** - Each module has a `*_FEATURE.md` file (e.g., `DatadogRUM/RUM_FEATURE.md`)

## Critical: Module Architecture

The SDK is organized as a **modular monorepo**. Understanding module dependencies is crucial:

```
DatadogInternal (shared protocols, types, utilities)
       ↑
       ├── DatadogCore (SDK initialization, data pipeline, networking)
       ├── DatadogLogs
       ├── DatadogTrace
       ├── DatadogRUM
       ├── DatadogSessionReplay
       ├── DatadogCrashReporting
       ├── DatadogWebViewTracking
       └── DatadogFlags
```

- Feature modules MUST NOT import each other
- Only DatadogCore may orchestrate feature lifecycles
- DatadogInternal is the ONLY allowed place for shared types

### IMPORTANT: Call Site Synchronization

**When modifying code in feature modules (Logs, Trace, RUM, etc.), you MUST check if any corresponding call sites in `DatadogCore` and `DatadogInternal` needs to be updated.**

Common oversight:
Agents modify a module's interface or behavior but forget to:
- Update how `DatadogCore` registers the feature
- Update the shared types present in `DatadogInternal`
- Update the manual data encoders (`SpanEventEncoder`, `LogEventEncoder`, ...) which leads to new attributes to not be reported
- Update integration points in other modules that depend on the changed code
- update ObjC bridges
Agents add, remove, move files but forget to:
- Update the corresponding pbxproj files accordingly.

**Always search for usages across the entire codebase before considering a change complete.**

## Data Flow

Understanding how data flows through the SDK is critical for making changes that propagate correctly.

### RUM Event Emission Pipeline

1. App calls public API (e.g., `RUMMonitor.shared().startView(...)`)
2. `Monitor` (concrete `RUMMonitorProtocol` implementation) creates a `RUMCommand` with timestamp, attributes, user ID
3. Command is enqueued to `FeatureScope` (async serial queue in `DatadogCore`)
4. `FeatureScope` invokes scope hierarchy: `RUMApplicationScope.process()` → `RUMSessionScope.process()` → `RUMViewScope.process()`
5. Each scope decides whether to accept, transform, or reject the command (returns `Bool` — `true` = scope stays open, `false` = scope is closed and removed from parent)
6. If valid, scope serializes to RUM event JSON and calls `writer.write(data:)`
7. `Writer` appends data to in-memory buffer or disk file
8. `DataUploadWorker` periodically reads batches of events from disk
9. `RequestBuilder` wraps batch in HTTP POST to Datadog intake
10. `HTTPClient` sends request; on success files are deleted; on failure backoff/retry applies

### State Management (Context)

1. Device/app/user state is collected in `DatadogContext`
2. Context is built by `DatadogContextProvider` from multiple publishers (user info, network state, battery, etc.)
3. Publishers subscribe to system notifications and update context in real-time
4. Context is passed to every scope during command processing
5. Scopes attach context fields to events before writing

## Key Abstractions

Agents must understand these abstractions to know WHERE to add code:

| Abstraction | Purpose | Examples |
|-------------|---------|----------|
| **Feature** | Represents a module (RUM, Logs, Trace). Conforms to `DatadogFeature` or `DatadogRemoteFeature`. | `RUMFeature`, `LogsFeature` |
| **Scope** | Hierarchical state container. Implements `process(command:context:writer:)` returning `Bool` (`true` = scope stays open, `false` = scope is closed and removed). | `RUMApplicationScope`, `RUMSessionScope`, `RUMViewScope` |
| **Command** | User action or system event triggering state changes. Struct with timestamp, attributes. | `RUMStartViewCommand`, `RUMAddUserActionCommand` |
| **Storage & Upload** | Persist events and batch-transmit to backend. | `FeatureStorage`, `FileWriter`, `DataUploadWorker` |
| **Context Provider** | Publishes system/app state changes. Implements `ContextValuePublisher`. | `UserInfoPublisher`, `NetworkConnectionInfoPublisher` |
| **Message Bus** | Inter-feature pub/sub communication. Protocol (`FeatureMessageReceiver`) in `DatadogInternal/Sources/MessageBus/`; concrete `MessageBus` in `DatadogCore/Sources/Core/MessageBus.swift`. | `MessageBus`, `FeatureMessageReceiver` |

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

## RFC Process for Major Changes

**Major behavioral changes require a Request for Comments (RFC) process.**

If you're about to make a change that:
- Modifies SDK public API significantly
- Changes data collection behavior
- Affects SDK initialization or lifecycle
- Introduces new configuration options
- Changes network request format or frequency

**→ STOP and inform the engineer.** Such changes:
1. Require internal RFC approval
2. May need cross-platform alignment with other SDKs (Android, Browser, React Native, Flutter, ...)
3. Must consider backwards compatibility

## SDK Philosophy

From `ZEN.md` - these principles guide all development:

1. **Zero crashes caused by SDK code** - Prefer making the SDK non-operational over throwing exceptions
2. **Small footprint** - Minimize runtime performance impact, library size, and network load
3. **Stability** - Avoid breaking changes; minor updates must be transparent
4. **Compatibility** - Support iOS 12.0+, both Swift and Objective-C

Agents must assume the SDK is used in thousands of apps in production. Any change that may alter behavior must be treated as a potential breaking change.

## Code Structure

```
dd-sdk-ios/
├── DatadogInternal/     # Shared protocols, types, utilities
│   ├── Sources/
│   └── Tests/
├── DatadogCore/         # Core SDK: initialization, pipeline, networking
│   ├── Sources/
│   └── Tests/
├── DatadogLogs/         # Logging feature
├── DatadogTrace/        # Local and Distributed tracing
├── DatadogRUM/          # Real User Monitoring
├── DatadogSessionReplay/# Session Replay
├── DatadogCrashReporting/ # Crash Reporting
├── DatadogWebViewTracking/ # Connecting RUM sessions from mobile apps to RUM sessions happening within WebViews
├── DatadogFlags/        # Feature flags
├── TestUtilities/       # Shared test mocks and helpers
├── IntegrationTests/    # UI and integration tests
├── BenchmarkTests/      # Performance benchmarks
├── E2ETests/            # End-to-end tests
└── tools/               # Build, lint, and code generation tools
```

### Where to Add New Code

**New Feature Module (e.g., DatadogNotifications):**
1. Create `DatadogNotifications/` with `Sources/` and `Tests/` subdirectories
2. Entry point: `Notifications.swift`, config: `NotificationsConfiguration.swift`
3. Feature plugin: `Feature/NotificationsFeature.swift` (implements `DatadogRemoteFeature`)
4. Update `Datadog.xcworkspace` and any relevant `.pbxproj` files

**New RUM Instrumentation:**
1. Create files in `DatadogRUM/Sources/Instrumentation/<InstrumentationName>/`
2. Follow existing patterns (e.g., `Resources/`, `Actions/`, `AppHangs/`, `Views/`)
3. Register in `RUMInstrumentation.swift`
4. Add tests in `DatadogRUM/Tests/RUMTests/Instrumentation/`

**New RUM Command:**
1. Add struct to `DatadogRUM/Sources/RUMMonitor/RUMCommand.swift` (implements `RUMCommand` protocol)
2. Add processing logic in the appropriate scope (`RUMApplicationScope`, `RUMSessionScope`, `RUMViewScope`)
3. Add tests in `DatadogRUM/Tests/RUMTests/Scopes/`

**New Context Provider:**
1. Create `DatadogCore/Sources/Core/Context/<ProviderName>Publisher.swift`
2. Implement `ContextValuePublisher` protocol
3. Subscribe to system notifications as needed
4. Register in `DatadogContextProvider.swift` initialization
5. Add tests in `DatadogCore/Tests/`

**Shared Internal Types (used by multiple features):**
1. Add to `DatadogInternal/Sources/` in the appropriate subdirectory (`Attributes/`, `Codable/`, `Context/`)
2. Add tests in `DatadogInternal/Tests/`

## Testing

### Test Conventions
- **Follow existing patterns** — Look at sibling test files for conventions
- Use `TestUtilities` for mocks and helpers
- Do not test Apple frameworks
- Do not test purely generated code
- Do not mock DatadogCore incorrectly (use provided helpers)

### Mock Infrastructure

| Mock Protocol | Usage | Example |
|---------------|-------|---------|
| `.mockAny()` | Deterministic default — use when specific value doesn't matter | `DatadogContext.mockAny()` |
| `.mockRandom()` | Randomized value — use for fuzz/property testing | `String.mockRandom()` |
| `.mockWith(...)` | Customizable mock with named parameters for specific fields | `.mockWith(service: "test")` |

### Key Test Types

| Type | Purpose | Location |
|------|---------|----------|
| `DatadogCoreProxy` | In-memory SDK instance that intercepts all events for assertions | `TestUtilities/Sources/Proxies/DatadogCoreProxy.swift` |
| `ServerMock` | HTTP mock server for network tests | `TestUtilities/Sources/Proxies/ServerMock.swift` |
| `HTTPClientMock` | Mock HTTP client | `TestUtilities/Sources/Mocks/DatadogCore/` |
| `PassthroughCoreMock` | Lightweight core mock that passes events through | `TestUtilities/Sources/Mocks/DatadogInternal/` |
| `FeatureScopeMock` | Mock feature scope for isolated testing | `TestUtilities/Sources/Mocks/DatadogInternal/` |
| `RUMSessionMatcher` | Groups RUM events by session, validates consistency | `TestUtilities/Sources/Matchers/` |

### DatadogCoreProxy Usage Pattern

```swift
let core = DatadogCoreProxy(context: .mockWith(service: "test-service"))
defer { core.flushAndTearDown() }

RUM.enable(with: config, in: core)
let monitor = RUMMonitor.shared(in: core)
monitor.startView(key: "view1")

let events = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
XCTAssertEqual(events.count, 1)
```

### SwiftLint for Tests
Separate lint rules (`tools/lint/tests.swiftlint.yml`) — more permissive than sources:
- Force unwrapping and force try are allowed in tests
- Same TODO-with-JIRA requirement applies

### Running Tests
```bash
# Unit tests for a specific scheme
make test-ios SCHEME="DatadogCore iOS"
make test-ios SCHEME="DatadogInternal iOS"

# All iOS unit tests
make test-ios-all

# UI/Integration tests
make ui-test TEST_PLAN="Default"

# Session Replay snapshot tests
make sr-snapshot-test
```

## Linting

The project uses SwiftLint with custom rules:

```bash
# Run linter
./tools/lint/run-linter.sh

# Auto-fix violations
./tools/lint/run-linter.sh --fix
```

Do not disable lint rules except where the rule is incorrect and a Jira ticket exists to track reinstating it.

## Building

```bash
# Initial setup
make                    # Full setup (env-check, repo-setup, dependencies)
make dependencies       # Carthage dependencies only

# SPM builds
make spm-build-ios
make spm-build-tvos

# Clean
make clean
```

## API Surface

Public API changes are tracked and verified:

```bash
# Generate API surface files
make api-surface

# Verify API surface hasn't changed unexpectedly
make api-surface-verify
```

## Code Generation

RUM and Session Replay data models are generated from schemas:

```bash
# Generate RUM models
make rum-models-generate

# Generate Session Replay models  
make sr-models-generate

# Verify models match schema
make rum-models-verify
make sr-models-verify
```

## File Headers

All source files must include the Apache License header:

```swift
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
```

## Error Handling Strategy

The SDK must **never throw exceptions** to customer code. All errors are handled internally:

- **NOP implementations**: `NOPMonitor`, `NOPDatadogCore` are used when SDK is not initialized or a feature is disabled. These silently accept all API calls.
- **Validation at boundaries**: Invalid input (blank strings, invalid URLs) is logged via `DD.logger` and ignored.
- **Scope `Bool` return**: Scope `process()` returns `Bool` to control scope lifecycle. `true` = scope stays open; `false` = scope is closed and removed from its parent's child array. This is a lifecycle signal, not a propagation signal.
- **Upload backoff**: Upload failures trigger exponential backoff and retry. Network errors are logged but never crash.
- **User callback safety**: Exceptions in user-provided callbacks (e.g., event mappers) are caught and logged.

## Thread Safety Rules

- **`@ReadWriteLock`**: Property wrapper for concurrent read, exclusive write access. Use for shared mutable state.
- **Serial queues**: Scope processing uses serial dispatch queues (`FeatureScope` is serial).
- **No `DispatchQueue.main.sync`**: Forbidden — prevents deadlocks.
- **Prefer `ReadWriteLock` wrappers**: Use `@ReadWriteLock` for new code. Exception: `NSLock` is used in method swizzling code (`DatadogInternal/Sources/Swizzling/`, `DatadogInternal/Sources/NetworkInstrumentation/`) where low-level synchronization is required — do not refactor those.
- **No thread spawning**: SDK uses system background queues (`qos: .utility`), never creates threads.

## Known Concerns & Fragile Areas

Agents must be aware of these fragile areas to avoid making them worse:

| Area | Location | Risk |
|------|----------|------|
| **SwiftUI view name extraction** | `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/` | Uses `Mirror`/`String(describing:)` reflection — fragile across Swift compiler versions |
| **UIKit method swizzling** | `DatadogRUM/Sources/Instrumentation/` | Depends on UIKit internal method signatures — iOS version changes could break silently |
| **KSCrash report parsing** | `DatadogCrashReporting/Sources/` | Parsing C-level crash reports depends on KSCrash output format |
| **Optional precondition in RUMSessionScope** | `RUMMonitor/Scopes/RUMSessionScope.swift` | Silent in production, crashes in debug — masks invalid state |
| **500 concurrent feature operations** | `RUMFeatureOperationManager.swift` | Active operations capped at 500 with `Set<String>` tracking |
| **Message bus queue unbounded** | `DatadogCore/Sources/Core/MessageBus/` | No queue depth limit — burst messaging could cause memory pressure |

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
- Protocols: `{Feature}Protocol.swift`

## Conditional Compilation

- `SPM_BUILD` — defined when building via Swift Package Manager
- `DD_BENCHMARK` — defined for benchmark builds
- `DD_COMPILED_FOR_INTEGRATION_TESTS` — toggles `@testable` imports for integration tests
- Platform checks: `#if os(iOS)`, `#if canImport(UIKit)`, `#if os(tvOS)`

## Dependencies

- **KSCrash 2.5.0**: Crash detection and reporting (`DatadogCrashReporting`). Products: Recording (crash detection), Filters (report processing).
- **opentelemetry-swift-core 2.3.0+**: OpenTelemetry API for distributed tracing (`DatadogTrace`). Two compilation modes:
  - Default: Lightweight OpenTelemetry API mirror (https://github.com/DataDog/opentelemetry-swift-packages)
  - Full: Set `OTEL_SWIFT` env var — requires iOS 13+ and adds significant dependency tree

Avoid adding new dependencies unless absolutely necessary (small footprint principle).

## Extension Libraries

- **Datadog Integration for Apollo iOS**: https://github.com/DataDog/dd-sdk-ios-apollo-interceptor, extracts GraphQL Operation information automatically from GraphQL Requests to let DatadogRUM enrich GraphQL RUM Resources

## Forbidden Actions for Agents
- Do NOT modify generated files (RUM and Session Replay models)
- Do NOT add new dependencies without explicit approval
- Do NOT change networking formats or endpoints
- Do NOT introduce new public API without RFC review
- Do NOT edit build scripts unless instructed
- NEVER mention AI assistant names (Claude, ChatGPT, Cursor, Copilot, etc.) in: Commit messages, PR descriptions, Code comments, Co-author tags

## Platform Support

- iOS 12.0+ (iOS 13.0+ with full OpenTelemetry)
- tvOS 12.0+
- macOS 12.6+ (limited modules)
- watchOS 7.0+ (limited modules)

Agents must not introduce APIs that require newer OS versions unless approved.

## Continuous learning

When discovering new patterns or common mistakes during tasks,
update this file to help future agents avoid the same pitfalls.

## Quick Reference

| Task | Command |
|------|---------|
| Setup | `make` |
| Lint | `./tools/lint/run-linter.sh` |
| Test iOS | `make test-ios SCHEME="<scheme>"` |
| All iOS tests | `make test-ios-all` |
| UI tests | `make ui-test TEST_PLAN="Default"` |
| Build SPM | `make spm-build-ios` |
| API surface | `make api-surface` |

