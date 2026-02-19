# DatadogInternal — Agent Guide

> Module-specific guidance for the shared internal module. For project-wide rules, see the root `AGENTS.md`.

## Module Overview

DatadogInternal is the **shared contract layer** — it defines protocols, types, and utilities used by all other modules. It has no external dependencies (Foundation only). Feature modules and DatadogCore both depend on it, but it depends on nothing else.

**Critical rule:** This module defines interfaces; `DatadogCore` provides the concrete implementations.

## Key Protocols

| Protocol | Purpose | Location |
|----------|---------|----------|
| `DatadogCoreProtocol` | Central injectable core interface | `Sources/DatadogCoreProtocol.swift` |
| `DatadogFeature` | Base protocol for feature modules | `Sources/DatadogFeature.swift` |
| `DatadogRemoteFeature` | Extension adding `requestBuilder` for features that upload data | `Sources/DatadogFeature.swift` |
| `FeatureScope` | Provides features with event writing, context, and storage | `Sources/FeatureScope.swift` |
| `FeatureMessageReceiver` | Receives inter-feature messages via the bus | `Sources/MessageBus/` |
| `ContextValuePublisher` | Publishes context value changes | `Sources/Context/` |
| `FeatureRequestBuilder` | Builds HTTP requests for feature data upload | `Sources/Upload/` |
| `DataEncryption` | Optional encryption for on-disk data | `Sources/Storage/` |

## Generated Models — DO NOT EDIT

The following directories contain **auto-generated** code from the [rum-events-format](https://github.com/DataDog/rum-events-format) schema:

- `Sources/Models/RUM/` — RUM event models (`RUMDataModels.swift`)
- `Sources/Models/SessionReplay/` — Session Replay models
- `Sources/Models/Logs/` — Log event models
- `Sources/Models/Trace/` — Trace/span models
- `Sources/Models/CrashReporting/` — Crash report models
- `Sources/Models/Profiling/` — Profiling models
- `Sources/Models/WebViewTracking/` — WebView tracking models

**Regenerate with:** `make rum-models-generate GIT_REF=master`
**Verify with:** `make rum-models-verify`

Never hand-edit these files. Changes must go through the schema repo and regeneration pipeline.

## Directory Structure

| Directory | Contents |
|-----------|----------|
| `Sources/Attributes/` | Attribute encoding/decoding utilities |
| `Sources/BacktraceReporting/` | Stack trace collection |
| `Sources/Codable/` | JSON encoding utilities |
| `Sources/Concurrency/` | Thread-safety primitives (`ReadWriteLock`, etc.) |
| `Sources/Context/` | `DatadogContext`, publishers, system info types |
| `Sources/MessageBus/` | Inter-feature message passing protocol |
| `Sources/Models/` | Generated event models (RUM, Logs, Trace) |
| `Sources/NetworkInstrumentation/` | URL session swizzling base for auto-instrumentation |
| `Sources/Storage/` | `FeatureStorage` protocol and related types |
| `Sources/Telemetry/` | SDK self-monitoring |
| `Sources/Upload/` | `FeatureUpload`, `FeatureRequestBuilder`, `URLRequestBuilder` |
| `Sources/Utils/` | Helpers (Date, UUID, JSON, etc.) |

## Context Types

`DatadogContext` (`Sources/Context/`) is the central context object passed to all features:
- Device info, OS version, app state
- User info (ID, name, email, custom attributes)
- Network connection info
- Session ID, view ID
- Tracking consent state
- SDK version, source type

When adding a new context field:
1. Add the property to `DatadogContext` here
2. Create a `ContextValuePublisher` here
3. Register the publisher in `DatadogCore`'s `DatadogContextProvider`

## Upload Infrastructure

- `URLRequestBuilder` — Builds HTTP requests with DD headers (API key, origin, version)
- `FeatureRequestBuilder` — Protocol for feature-specific request building
- Header constants and endpoint logic
- Location: `Sources/Upload/`

## Important for Agents

- Changes to protocols here affect ALL modules. Proceed with extreme caution.
- Adding a new field to `DatadogContext` requires updates in `DatadogCore` (publisher) and potentially in feature modules (usage).
- Never add external dependencies to this module.

## Code Style Rules

- `explicit_top_level_acl` — all declarations must have explicit access control (`public`, `internal`, `private`)
- `@testable import` — only in test targets, never in production code
- Imports: module imports at top, `Foundation` is the only allowed external dependency in this module
- All TODOs must reference JIRA: `// TODO: RUM-1234 description`

## Reference Documentation

- Root `AGENTS.md` — Project-wide rules, data flow, and conventions
