# AI Agents Guide for dd-sdk-ios

> This document outlines the rules, constraints, and expectations for AI agents contributing to the Datadog iOS SDK. Because the SDK powers mission-critical telemetry for thousands of customer applications, all changes must preserve stability, compatibility, and performance. Agents must strictly follow the guidelines below when navigating the repository, modifying code, or generating pull requests.

## Project Overview

The SDK is responsible for reliably collecting, batching, and transmitting telemetry from customer apps under strict performance, safety, and compliance constraints.

This is the **Datadog SDK for iOS and tvOS** - Swift and Objective-C libraries to interact with Datadog. The SDK enables:
- **Logs**: Send logs to Datadog
- **Traces**: Distributed tracing
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
       │        ↑
       │        ├── DatadogLogs
       │        ├── DatadogTrace
       │        ├── DatadogRUM
       │        ├── DatadogSessionReplay
       │        ├── DatadogCrashReporting
       │        ├── DatadogWebViewTracking
       │        └── DatadogFlags
```

- Feature modules MUST NOT import each other
- Only DatadogCore may orchestrate feature lifecycles
- DatadogInternal is the ONLY allowed place for shared types

### IMPORTANT: Call Site Synchronization

**When modifying code in feature modules (Logs, Trace, RUM, etc.), you MUST check and update corresponding call sites in `DatadogCore` and `DatadogInternal`.**

Common oversight:
Agents modify a module's interface or behavior but forget to:
- Update how `DatadogCore` initializes or registers the feature
- Update extraction/encoding logic in `DatadogInternal`
- Update integration points in other modules that depend on the changed code
- update ObjC bridges when needed
Agents add, remove, move files but forget to:
- Update the corresponding pbxproj files accordingly.

**Always search for usages across the entire codebase before considering a change complete.**

## Commit & PR Conventions

### Commit Requirements
- **All commits MUST be signed** (GPG or SSH signature)
- **Prefix**: `[RUM-XXXX]` where XXXX is the JIRA ticket number. It applies only for internal development. Third party contributions do not need it.
- Example: `[RUM-1234] Add baggage header merging support`

### PR Requirements
- **Title prefix**: `[RUM-XXXX]` matching the JIRA ticket
- Include thorough test coverage
- Pass all CI checks (lint, tests, API surface verification)

## RFC Process for Major Changes

**Major behavioral changes require a Request for Comment (RFC) process.**

If you're about to make a change that:
- Modifies SDK public API significantly
- Changes data collection behavior
- Affects SDK initialization or lifecycle
- Introduces new configuration options
- Changes network request format or frequency

**→ STOP and inform the engineer.** Such changes:
1. Require internal RFC approval
2. May need cross-platform alignment (Android, Browser, React Native SDKs)
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
├── DatadogWebViewTracking/ # Connecting RUM sessions from mobile apps to RUM sessions hapening within WebViews
├── DatadogFlags/        # Feature flags
├── TestUtilities/       # Shared test mocks and helpers
├── IntegrationTests/    # UI and integration tests
├── BenchmarkTests/      # Performance benchmarks
├── E2ETests/            # End-to-end tests
└── tools/               # Build, lint, and code generation tools
```

## Testing

### Test Conventions
- **Follow existing patterns** - Look at sibling test files for conventions
- Use `TestUtilities` for mocks and helpers
- Mock naming: `static func mockAny()` for any value, descriptive names for specific scenarios
- Use `DatadogCoreProxy` for integration testing features
- Do not test Apple frameworks
- Do not test purely generated code
- Do not mock DatadogCore incorrectly (use provided helpers)

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

### Key Lint Rules
- **TODO comments must include JIRA reference**: `// TODO: RUM-123 description`
- **No `UIApplication.shared`**: Use `UIApplication.managedShared` instead
- **No `URLRequest.allHTTPHeaderFields`**: Use `URLRequest.value(forHTTPHeaderField:)` 
- **Avoid Required Reason API conflicts**: Don't use names that conflict with Apple's privacy APIs

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

## Dependencies

- **PLCrashReporter**: Crash reporting (via Carthage)
- **OpenTelemetryApi**: Distributed tracing (via SPM)

Avoid adding new dependencies unless absolutely necessary (small footprint principle).

## Forbidden Actions for Agents
- Do NOT modify generated files (RUM and Session Replay models)
- Do NOT add new dependencies without explicit approval
- Do NOT change networking formats or endpoints
- Do NOT introduce new public API without RFC review
- Do NOT edit build scripts unless instructed

## Platform Support

- iOS 12.0+ (iOS 13.0+ with full OpenTelemetry)
- tvOS 12.0+
- macOS 12.6+ (limited modules)
- watchOS 7.0+ (limited modules)

Agents must not introduce APIs that require newer OS versions unless approved.

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

