# DatadogRUM — Agent Guide

> Module-specific guidance for the RUM (Real User Monitoring) module. For project-wide rules, see the root `AGENTS.md`.

## Module Overview

DatadogRUM is the most complex module in the SDK. It tracks user sessions, views, actions, resources, errors, and long tasks by processing commands through a hierarchical scope tree.

## Scope Hierarchy

Commands flow top-down through scopes. Each scope decides whether to accept, transform, or reject a command:

```
RUMApplicationScope          # Top-level — manages session lifecycle
  └── RUMSessionScope        # Session-level — sampling, session state
        └── RUMViewScope     # View-level — largest file, manages child scopes
              ├── RUMResourceScope    # Network resource tracking
              ├── RUMUserActionScope  # User action tracking (tap, scroll, etc.)
              └── RUMLongTaskScope    # Long task detection
```

- Each scope implements `process(command:context:writer:)` returning `Bool`
- `true` = scope stays open; `false` = scope is closed and removed from its parent's child array
- Parent scopes `filter` children by this return value — returning `false` destroys the scope
- Scopes create/manage child scopes dynamically
- View scope is the workhorse — it owns resources, actions, long tasks

## Key Files Map

| File | Role |
|------|------|
| `Sources/RUM.swift` | Feature entry point (`RUM.enable()`) |
| `Sources/RUMConfiguration.swift` | Configuration (sessionSampleRate, applicationID, etc.) |
| `Sources/RUMMonitorProtocol.swift` | Public API protocol |
| `Sources/RUMMonitorProtocol+Convenience.swift` | Convenience extensions |
| `Sources/RUMMonitor.swift` | Public `RUMMonitor.shared()` accessor |
| `Sources/RUMMonitor/Monitor.swift` | Concrete `RUMMonitorProtocol` implementation |
| `Sources/RUMMonitor/RUMCommand.swift` | All command types (large file) |
| `Sources/RUMMonitor/RUMScope.swift` | Scope protocol |
| `Sources/RUMMonitor/Scopes/` | All scope implementations |
| `Sources/RUMMonitor/Scopes/RUMFeatureOperationManager.swift` | Feature operation vital tracking |
| `Sources/Feature/RUMFeature.swift` | Feature plugin (`DatadogRemoteFeature` conformance) |
| `Sources/Feature/RequestBuilder.swift` | HTTP request building for upload |
| `Sources/Instrumentation/` | Auto-instrumentation hooks |

## RUMCommand Pattern

All public API calls are translated into commands before processing:

1. Public method on `Monitor.swift` validates inputs
2. Creates a command struct (e.g., `RUMStartViewCommand`) with UUID, timestamp, attributes
3. Dispatches command to `FeatureScope` (async serial queue)
4. Scope hierarchy processes the command

When adding a new command:
- Add the struct to `RUMCommand.swift`
- Implement the `RUMCommand` protocol
- Add processing in the appropriate scope's `process()` method
- Add tests in `Tests/RUMTests/Scopes/`

## RUMFeatureOperationManager

Tracks feature operations (vital signals) with these constraints:
- Active operations tracked via `Set<String>` with key `"\(name)\(operationKey ?? "")"`
- **Hard limit: 500 concurrent operations** — exceeded operations are logged and dropped
- UUID generated at Monitor level before creating command
- Validation in FeatureOperationManager with `DD.logger.error()` on failure

## Event Mappers

Event mappers allow customers to modify or drop events before they are sent:
- **View events cannot be dropped** (mapper can modify but must return a value)
- All other event types (resource, action, error, long task) can be dropped by returning `nil`
- Exceptions in mapper callbacks are caught and logged — original event is sent

## Instrumentation Hooks

Auto-instrumentation lives in `Sources/Instrumentation/`:

| Hook | Location | Notes |
|------|----------|-------|
| URLSession | `Resources/` | Network resource tracking |
| View tracking | `Views/` | Automatic view tracking (UIKit and SwiftUI) |
| SwiftUI Views | `Views/SwiftUI/` | Uses `Mirror` reflection — **fragile** |
| User Actions | `Actions/` | User action auto-detection (gestures) |
| App Hang | `AppHangs/` | ANR detection |
| Long Tasks | `LongTasks/` | Long task detection |
| Memory Warnings | `MemoryWarnings/` | Memory warning tracking |
| Watchdog Terminations | `WatchdogTerminations/` | OOM and watchdog kill tracking |
| App State | `AppState/` | App lifecycle state tracking |

## Testing This Module

- Use `DatadogCoreProxy` for integration-style tests (see `TestUtilities/AGENTS.md`)
- Use `RUMSessionMatcher` to group and validate events by session
- Mock dependencies via `RUMScopeDependencies` (constructor injection)
- Tests live in `Tests/RUMTests/` mirroring source structure

## Known Fragile Areas

Agents must exercise extra caution with these areas:

1. **SwiftUI reflection** (`Instrumentation/Views/SwiftUI/`): Uses `String(describing:)` which is not a stable API. Do not change reflection logic without extensive testing across Xcode versions.
2. **UIKit swizzling** (`Instrumentation/`): Method swizzling depends on UIKit internal signatures. Changes risk silent breakage on new iOS versions.
3. **Optional precondition in RUMSessionScope**: Contains a conditional precondition that is silent in production but crashes in debug. Be aware of this when modifying session state logic.
4. **User action 100ms window** (`RUMUserActionScope`): Discrete user actions have a hardcoded 100ms window — actions arriving after are dropped.

## Reference Documentation

- `RUM_FEATURE.md` (this directory) — Public API and feature documentation
- Root `AGENTS.md` — Project-wide rules, data flow, and conventions
