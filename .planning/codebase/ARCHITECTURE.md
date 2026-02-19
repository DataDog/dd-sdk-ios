# Architecture

**Analysis Date:** 2026-02-19

## Pattern Overview

**Overall:** Modular feature-based monorepo with message-bus inter-feature communication and scope hierarchy for state management.

**Key Characteristics:**
- Each SDK feature (Logs, Trace, RUM, SessionReplay, etc.) is an independent module
- Features do not import each other; coordination happens through `DatadogCore`
- Data flows through a scope hierarchy: Application → Session → View → User Action
- Events are accumulated in memory, written to disk via `Writer`, batched, and uploaded via `DataUploadWorker`
- Configuration is immutable; features subscribe to context/state changes via publishers

## Layers

**Feature Layer (e.g., DatadogRUM):**
- Purpose: Expose public APIs and orchestrate feature-specific logic
- Location: `DatadogRUM/Sources/`, `DatadogLogs/Sources/`, `DatadogTrace/Sources/`
- Contains: Public protocol (`RUMMonitorProtocol`), configuration (`RUM.Configuration`), commands, scope hierarchy
- Depends on: `DatadogCore`, `DatadogInternal`
- Used by: Application code

**Core Layer (DatadogCore):**
- Purpose: Initialize SDK, manage features, provide storage/upload pipeline, maintain context
- Location: `DatadogCore/Sources/Core/`
- Contains: `DatadogCore` (main orchestrator), `MessageBus` (inter-feature pub/sub), storage/upload machinery, context providers
- Depends on: `DatadogInternal`
- Used by: All feature modules

**Internal Layer (DatadogInternal):**
- Purpose: Shared protocols, types, and utilities used across all modules
- Location: `DatadogInternal/Sources/`
- Contains: `DatadogCoreProtocol`, `DatadogFeature`, `DatadogContext`, message bus protocol, storage/upload protocols, encoders, publishers
- Depends on: Foundation only
- Used by: All feature modules, `DatadogCore`

**Test Utilities Layer:**
- Purpose: Mocks, fakes, and test helpers shared across unit tests
- Location: `TestUtilities/Sources/`
- Contains: `DatadogCoreProxy` (fake SDK instance), mock objects, test data factories
- Depends on: `DatadogInternal` and target module
- Used by: Unit tests within each module

## Data Flow

**RUM Event Emission (Typical):**

1. App calls public API: `RUMMonitor.shared().startView(...)`
2. `RUMMonitor.shared()` retrieves feature from `CoreRegistry` and returns `Monitor` (concrete implementation of `RUMMonitorProtocol`)
3. `Monitor` creates a `RUMCommand` (e.g., `RUMStartViewCommand`) with timestamp, attributes, user ID
4. Command is enqueued to `FeatureScope` (async queue in `DatadogCore`)
5. `FeatureScope` invokes scope hierarchy: `RUMApplicationScope.process()` → `RUMSessionScope.process()` → `RUMViewScope.process()`
6. Each scope decides whether to accept, transform, or reject the command
7. If valid, scope serializes to RUM event JSON and calls `writer.write(data:)`
8. `Writer` (async) appends data to in-memory buffer or disk file
9. `DataUploadWorker` periodically reads batches of events from disk (via `DataReader`)
10. `RequestBuilder` wraps batch in HTTP POST to Datadog intake
11. `HTTPClient` sends request; on success, files are deleted; on failure, backoff/retry logic applies

**State Management (Context):**

1. Device/app/user state is collected in `DatadogContext` (device model, OS, user ID, session ID, view ID, etc.)
2. Context is built by `DatadogContextProvider` from multiple publishers (user info, network state, battery, etc.)
3. Publishers are subscribed to system notifications and update context in real-time
4. Context is passed to every scope during command processing
5. Scopes attach context fields to events before writing

## Key Abstractions

**Feature (DatadogFeature):**
- Purpose: Represents a feature module (RUM, Logs, Trace, etc.)
- Examples: `RUMFeature`, `LogsFeature` (in private core)
- Pattern: Conforms to `DatadogFeature` or `DatadogRemoteFeature`; must implement `messageReceiver` and (for remote features) `requestBuilder`

**Scope (RUMScope, etc.):**
- Purpose: Hierarchical state container for feature-specific logic
- Examples: `RUMApplicationScope`, `RUMSessionScope`, `RUMViewScope`, `RUMResourceScope`
- Pattern: Implements `process(command:context:writer:)` returning `Bool` (continue processing?); may create/manage child scopes

**Command (RUMCommand, etc.):**
- Purpose: User action or system event that triggers feature state changes
- Examples: `RUMStartViewCommand`, `RUMAddUserActionCommand`, `RUMResourceStartCommand`
- Pattern: Struct carrying timestamp, attributes, and decision hints (e.g., `canStartBackgroundView`)

**Storage & Upload:**
- Purpose: Persist events and batch-transmit to backend
- Examples: `FeatureStorage`, `FileWriter`, `DataUploadWorker`
- Pattern: Features write to `FeatureStorage` (abstraction), which routes to `FileWriter`; upload worker reads from storage, builds requests, sends via HTTP client

**Context Providers (Publishers):**
- Purpose: Publish system/app state changes and inject into context
- Examples: `UserInfoPublisher`, `NetworkConnectionInfoPublisher`, `ApplicationStatePublisher`
- Pattern: Implement `ContextValuePublisher` protocol; emit value changes via subject/callback

## Entry Points

**SDK Initialization:**
- Location: `DatadogCore/Sources/Datadog.swift` (entry enum)
- Triggers: App calls `Datadog.initialize(with:trackingConsent:)`
- Responsibilities: Create `DatadogCore` instance, register in `CoreRegistry`, set up context providers, storage, HTTP client

**Feature Enablement:**
- Location: `DatadogRUM/Sources/RUM.swift`, `DatadogLogs/Sources/Logs.swift`, etc.
- Triggers: App calls `RUM.enable(with:)` after `Datadog.initialize()`
- Responsibilities: Create feature instance (e.g., `RUMFeature`), register with `DatadogCore`, return public monitor interface

**RUM Manual Interaction:**
- Location: `DatadogRUM/Sources/RUMMonitor.swift`
- Triggers: App calls `RUMMonitor.shared().startView()`, `addError()`, etc.
- Responsibilities: Retrieve feature from core, invoke monitor methods, which create commands and queue to feature scope

**Message Bus Inter-Feature Communication:**
- Location: `DatadogCore/Sources/Core/MessageBus.swift`
- Triggers: One feature publishes a message (e.g., crash event)
- Responsibilities: Route message to subscribed features via `FeatureMessageReceiver`

## Error Handling

**Strategy:** Never throw exceptions from SDK code; prefer logging and gracefully degrading functionality.

**Patterns:**
- SDK maintains no-op implementations (`NOPMonitor`, `NOPDatadogCore`) for when SDK is not initialized or feature is disabled
- Validation happens at public API boundaries; invalid input is logged and ignored
- Scope processing uses `Bool` return to stop propagation on error
- Upload failures trigger exponential backoff and retry; network errors are logged but don't crash
- Exceptions in user-provided callbacks (e.g., event mappers) are caught and logged

## Cross-Cutting Concerns

**Logging:**
- Internal SDK logging via `InternalLogger` (in `DatadogInternal`)
- Configurable verbosity level: `Datadog.verbosityLevel`
- User-configurable via `DD.logger` extension
- Used for warnings, errors, debug info (no info-level logs to stdout by default)

**Validation:**
- Input validation at public API boundaries (non-blank strings, valid URLs)
- Command validation within scope hierarchy (e.g., is session active?)
- Attribute validation: safe encoding of user-provided attributes

**Authentication:**
- Client token provided at initialization
- Automatically attached to all HTTP requests by `URLSessionClient`
- No bearer token or session management; stateless auth

**Thread Safety:**
- Core and feature scopes use serial dispatch queues (`FeatureScope` is serial)
- Shared mutable state protected by `ReadWriteLock` (see `@ReadWriteLock` property wrapper)
- Publishers use dedicated queues for subscription callbacks
- No threads are spawned by SDK; uses system background queues (`qos: .utility`)

---

*Architecture analysis: 2026-02-19*
