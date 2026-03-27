# AI Agents Guide for dd-sdk-ios

> This document is the single source of truth for AI agent conventions, architecture, and development rules. Because the SDK powers mission-critical telemetry for thousands of customer applications, all changes must preserve stability, compatibility, and performance.

## Related Documentation

- **`docs/LLM_FEATURE_DOCS_GUIDELINES.md`** — Guidelines for creating and updating `*_FEATURE.md` files
- **`ZEN.md`** — Core SDK philosophy and principles
- **`CONTRIBUTING.md`** — General contribution guidelines
- **Feature-specific docs** — Each module has a `*_FEATURE.md` file (e.g., `DatadogRUM/RUM_FEATURE.md`)

## Module Architecture

The SDK is a **modular monorepo**:

```
DatadogInternal (shared protocols, types — Foundation only, no external deps)
    ├── DatadogCore (initialization, storage, upload)
    ├── DatadogLogs
    ├── DatadogTrace
    ├── DatadogRUM
    ├── DatadogSessionReplay
    ├── DatadogCrashReporting
    ├── DatadogWebViewTracking
    ├── DatadogFlags
    ├── DatadogProfiling
    └── TestUtilities (test-only, shared mocks/matchers)
```

- Feature modules MUST NOT import each other
- Only `DatadogCore` orchestrates feature lifecycles
- `DatadogInternal` is the ONLY allowed place for shared types — it defines interfaces; `DatadogCore` provides concrete implementations
- Platform support: iOS 12.0+, tvOS 12.0+, macOS 12.6+, watchOS 7.0+ (limited modules), visionOS

### IMPORTANT: Call Site Synchronization

**When modifying code in feature modules (Logs, Trace, RUM, etc.), you MUST check if any corresponding call sites in `DatadogCore` and `DatadogInternal` needs to be updated.**

- Forgetting to update how `DatadogCore` registers the feature
- Forgetting to update shared types in `DatadogInternal`
- Forgetting to update manual data encoders (`SpanEventEncoder`, `LogEventEncoder`, ...) — new attributes won't be reported
- Forgetting to update ObjC bridges
- Forgetting to update `.pbxproj` files when adding, removing, or moving files

**Always search for usages across the entire codebase before considering a change complete.**

## Data Flow

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

### Storage Pipeline

```
Feature writes event → AsyncWriter → FileWriter → FilesOrchestrator → disk file
                                                                         ↓
DataUploadWorker (periodic) → DataReader → RequestBuilder → HTTPClient → Datadog backend
```

- File-based storage in Application Support sandbox — no database
- Directory structure: `[AppSupport]/Datadog/[site]/[feature]/`
- Format: JSON for events, binary TLV encoding for compact storage
- Optional encryption via `DataEncryption` protocol
- Caching explicitly disabled at URLSession level (ephemeral config, `urlCache = nil`)
- Key-value storage: `FeatureDataStore` for feature-specific persistent data

### Feature Registration Lifecycle

1. App calls `Datadog.initialize(with:trackingConsent:)` — creates `DatadogCore` instance
2. `DatadogCore` is registered in `CoreRegistry` (singleton lookup)
3. App calls feature-specific `enable()` (e.g., `RUM.enable(with:in:)`)
4. Feature creates its plugin (e.g., `RUMFeature`) and registers with core
5. Core allocates storage directory and upload worker for the feature
6. Feature can now write events and receive messages via the bus

### State Management (Context)

`DatadogContext` is the central context object containing device info, app state, user info, network state, etc. It is built by `DatadogContextProvider` from multiple `ContextValuePublisher` instances that subscribe to system notifications and update context in real-time. Context is passed to every scope during command processing and attached to events before writing.

## Key Abstractions

| Abstraction | Purpose | Examples |
|-------------|---------|----------|
| **Feature** | Represents a module (RUM, Logs, Trace). Conforms to `DatadogFeature` or `DatadogRemoteFeature`. | `RUMFeature`, `LogsFeature` |
| **Scope** | Hierarchical state container. Implements `process(command:context:writer:)` returning `Bool` (`true` = scope stays open, `false` = scope is closed and removed). | `RUMApplicationScope`, `RUMSessionScope`, `RUMViewScope` |
| **Command** | User action or system event triggering state changes. Struct with timestamp, attributes. | `RUMStartViewCommand`, `RUMAddUserActionCommand` |
| **Storage & Upload** | Persist events and batch-transmit to backend. | `FeatureStorage`, `FileWriter`, `DataUploadWorker` |
| **Context Provider** | Publishes system/app state changes. Implements `ContextValuePublisher`. | `UserInfoPublisher`, `NetworkConnectionInfoPublisher` |
| **Message Bus** | Inter-feature pub/sub communication. Protocol (`FeatureMessageReceiver`) in `DatadogInternal/Sources/MessageBus/`; concrete `MessageBus` in `DatadogCore`. | `MessageBus`, `FeatureMessageReceiver` |

## Key Protocols

| Protocol | Purpose | Location |
|----------|---------|----------|
| `DatadogCoreProtocol` | Central injectable core interface | `DatadogInternal/Sources/DatadogCoreProtocol.swift` |
| `DatadogFeature` | Base protocol for feature modules | `DatadogInternal/Sources/DatadogFeature.swift` |
| `DatadogRemoteFeature` | Extension adding `requestBuilder` for features that upload data | `DatadogInternal/Sources/DatadogFeature.swift` |
| `FeatureScope` | Provides features with event writing, context, and storage | `DatadogInternal/Sources/FeatureScope.swift` |
| `FeatureMessageReceiver` | Receives inter-feature messages via the bus | `DatadogInternal/Sources/MessageBus/` |
| `ContextValuePublisher` | Publishes context value changes | `DatadogCore/Sources/Core/Context/ContextValuePublisher.swift` |
| `DataEncryption` | Optional encryption for on-disk data | `DatadogCore/Sources/Core/Storage/DataEncryption.swift` |

## SDK Philosophy (from ZEN.md)

1. **Zero crashes caused by SDK code** — Prefer making the SDK non-operational over throwing exceptions
2. **Small footprint** — Minimize runtime performance impact, library size, and network load
3. **Stability** — Avoid breaking changes; minor updates must be transparent
4. **Compatibility** — Support iOS 12.0+, both Swift and Objective-C

The SDK is used in thousands of production apps. Any change that may alter behavior must be treated as a potential breaking change.

## Error Handling Strategy

The SDK must **never throw exceptions** to customer code:

- **NOP implementations**: `NOPMonitor`, `NOPDatadogCore` silently accept all API calls when SDK is not initialized or a feature is disabled.
- **Validation at boundaries**: Invalid input is logged via `DD.logger` and ignored.
- **Upload backoff**: Upload failures trigger exponential backoff and retry. Network errors are logged but never crash.
- **User callback safety**: Exceptions in user-provided callbacks (e.g., event mappers) are caught and logged — original event is sent.
- **Event mappers**: View events cannot be dropped (mapper must return a value). All other event types can be dropped by returning `nil`.

## Thread Safety Rules

- **`@ReadWriteLock`**: Property wrapper for concurrent read, exclusive write access. Use for shared mutable state.
- **Serial queues**: Scope processing uses serial dispatch queues (`FeatureScope` is serial).
- **No `DispatchQueue.main.sync`**: Forbidden — prevents deadlocks.
- **NSLock exception**: `NSLock` is used in method swizzling code (`DatadogInternal/Sources/Swizzling/`, `DatadogInternal/Sources/NetworkInstrumentation/`) where low-level synchronization is required — do not refactor those.
- **No thread spawning**: SDK uses system background queues (`qos: .utility`), never creates threads.

## Known Concerns & Fragile Areas

| Area | Location | Risk |
|------|----------|------|
| **SwiftUI view name extraction** | `DatadogRUM/Sources/Instrumentation/Views/SwiftUI/` | Uses `Mirror`/`String(describing:)` reflection — fragile across Swift compiler versions. Do not change without extensive testing. |
| **UIKit method swizzling** | `DatadogRUM/Sources/Instrumentation/` | Depends on UIKit internal method signatures — iOS version changes could break silently |
| **KSCrash report parsing** | `DatadogCrashReporting/Sources/` | Parsing C-level crash reports depends on KSCrash output format |
| **Optional precondition in RUMSessionScope** | `RUMMonitor/Scopes/RUMSessionScope.swift` | Silent in production, crashes in debug — masks invalid state |
| **500 concurrent feature operations** | `RUMFeatureOperationManager.swift` | Active operations capped at 500 with `Set<String>` tracking |
| **Message bus queue unbounded** | `DatadogCore/Sources/Core/MessageBus/` | No queue depth limit — burst messaging could cause memory pressure |
| **User action 100ms window** | `RUMUserActionScope` | Discrete user actions have a hardcoded 100ms window — actions arriving after are dropped |

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

If you're about to make a change that modifies public API significantly, changes data collection behavior, affects initialization/lifecycle, introduces new configuration options, or changes network request format/frequency — **STOP and inform the engineer.** Such changes require internal RFC approval and cross-platform alignment.

## Where to Add New Code

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
2. Include timestamp, attributes, and any decision hints (e.g., `canStartBackgroundView`)
3. Add public API method to `RUMMonitorProtocol.swift` and implement in `Monitor.swift`
4. Add processing logic in the appropriate scope
5. Add tests in `DatadogRUM/Tests/RUMTests/Scopes/`
6. Update API surface: `make api-surface`

**New Context Provider:**
1. Add the property to `DatadogContext` in `DatadogInternal/Sources/Context/`
2. Create `DatadogCore/Sources/Core/Context/<ProviderName>Publisher.swift` implementing `ContextValuePublisher`
3. Subscribe to relevant system notifications
4. Register the publisher in `DatadogContextProvider` initialization
5. Add tests in `DatadogCore/Tests/`

**Shared Internal Types (used by multiple features):**
1. Add to `DatadogInternal/Sources/` in the appropriate subdirectory
2. Add tests in `DatadogInternal/Tests/`
3. Changes here affect ALL modules — proceed with extreme caution

## Testing

### Test Conventions
- **Follow existing patterns** — Look at sibling test files for conventions
- Use `TestUtilities` for mocks and helpers
- Do not test Apple frameworks
- Do not test purely generated code
- Do not mock DatadogCore incorrectly (use provided helpers)
- No `sleep()` in unit tests — use expectations or synchronous test queues

### Mock Infrastructure

| Convention | Usage | Example |
|------------|-------|---------|
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
defer { core.flushAndTearDown() }  // MUST be in defer

RUM.enable(with: config, in: core)
let monitor = RUMMonitor.shared(in: core)
monitor.startView(key: "view1")

let events = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
XCTAssertEqual(events.count, 1)
```

### SwiftLint for Tests
Tests use separate lint rules (`tools/lint/tests.swiftlint.yml`) — force unwrapping and force try are allowed. Same TODO-with-JIRA requirement applies.

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

## HTTP Upload Details

- **Auth**: Client token passed as `DD-API-KEY` header
- **Custom headers**: `DD-EVP-ORIGIN`, `DD-EVP-ORIGIN-VERSION`, `DD-REQUEST-ID`
- **Formats**: JSON, NDJSON (batches), multipart/form-data (Session Replay, crashes)
- **Compression**: Gzip (`Content-Encoding: gzip`)
- **Endpoints by site**: `.us1` → `browser-intake-datadoghq.com`, `.eu1` → `browser-intake-datadoghq.eu`, etc.
- **Header builder**: `DatadogInternal/Sources/Upload/URLRequestBuilder.swift`
- **Site definitions**: `DatadogInternal/Sources/Context/DatadogSite.swift`

## Dependencies

- **KSCrash 2.5.0**: Crash detection and reporting (`DatadogCrashReporting`)
- **opentelemetry-swift-core 2.3.0+**: OpenTelemetry API for distributed tracing (`DatadogTrace`). Default: lightweight API mirror. Full: set `OTEL_SWIFT` env var (requires iOS 13+).

Avoid adding new dependencies unless absolutely necessary (small footprint principle).

## Extension Libraries

- **Datadog Integration for Apollo iOS**: https://github.com/DataDog/dd-sdk-ios-apollo-interceptor, extracts GraphQL Operation information automatically from GraphQL Requests to let DatadogRUM enrich GraphQL RUM Resources

## File Headers

All source files must include the Apache License header:
```swift
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
```

## Forbidden Actions for Agents

- Do NOT modify generated files (RUM and Session Replay models)
- Do NOT add new dependencies without explicit approval
- Do NOT change networking formats or endpoints
- Do NOT introduce new public API without RFC review
- Do NOT edit build scripts unless instructed
- NEVER mention AI assistant names (Claude, ChatGPT, Cursor, Copilot, etc.) in commit messages, PR descriptions, code comments, or co-author tags

## Swizzling

The SDK uses Objective-C method swizzling to instrument UIKit and Foundation APIs transparently. Swizzling is a high-risk technique in an SDK context because **you never control the full runtime environment** — customer apps, third-party libraries (RxSwift, Alamofire, Firebase, …), and other SDKs may swizzle the same methods.

**→ Before writing or modifying any swizzle, read `docs/SWIZZLING.md`.**

It documents the mandatory patterns, known pitfalls, and real incidents that have caused production crashes.

Key rules at a glance:
- Every swizzled method must be treated as already swizzled by someone else — both before and after the SDK installs its swizzle
- Setter swizzles must include a **re-entrancy guard** per object identity to survive frameworks that call back into the swizzled setter from within their own swizzle
- Getter swizzles must **unwrap any internal proxy** so that user code observing the property sees the original value, not the SDK wrapper
- Proxy objects used for forwarding must guard `responds(to:)` against circular delegation chains

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
