---
last_updated: 2026-06-19
sdk_version: 3.12.0
verified_against_commit: 72544f987
tracked_files:
  - DatadogLogs/Sources/Logs.swift
  - DatadogLogs/Sources/Logger.swift
  - DatadogLogs/Sources/LoggerProtocol.swift
  - DatadogLogs/Sources/Logs+objc.swift
  - DatadogLogs/Sources/Log/LogEventEncoder.swift
  - DatadogLogs/Sources/Scrubbing/LogEventMapper.swift
---

# Logs Feature

## Overview

Logs sends structured log events to Datadog. Loggers are created per-component and support log levels, tags, custom attributes, and optional console output. Logs requires initialization via `Datadog.initialize()` before enabling.

**Platform**: iOS, tvOS, watchOS, visionOS

## Quick Start Example

```swift
import DatadogCore
import DatadogLogs

// 1. Initialize Core SDK first
Datadog.initialize(
    with: Datadog.Configuration(
        clientToken: "<client_token>",
        env: "<environment>"
    ),
    trackingConsent: .granted
)

// 2. Enable Logs
Logs.enable(
    with: Logs.Configuration(
        // Modify or drop log events before upload
        // Return nil to drop an event
        // Default: nil (no mapping)
        eventMapper: { logEvent in
            var modified = logEvent
            // Scrub sensitive data
            if modified.message.contains("password") {
                return nil // drop the event
            }
            return modified
        },

        // Custom intake endpoint for log data
        // Default: nil (uses Datadog intake)
        customEndpoint: nil
    )
)

// 3. (Optional) Add global attributes to all logs
Logs.addAttribute(forKey: "app.flavor", value: "release")
Logs.removeAttribute(forKey: "app.flavor")

// 4. Create a logger
let logger = Logger.create(
    with: Logger.Configuration(
        // Override the service name reported on logs
        // Default: nil (uses the SDK service value)
        service: "my-ios-app",

        // Logger name, reported as `logger.name` on log events
        // Default: nil (falls back to the app bundle identifier in the log payload)
        name: "MyViewController",

        // Attach network connectivity info (reachability, interface, carrier)
        // Default: false
        networkInfoEnabled: false,

        // Attach sampled-in RUM session, view and action IDs when available
        // Default: true
        bundleWithRumEnabled: true,

        // Attach active span and trace IDs when available
        // Default: true
        bundleWithTraceEnabled: true,

        // Sampling rate for remote log upload (0 = none sent, 100 = all sent)
        // Default: 100.0
        remoteSampleRate: 100.0,

        // Minimum log level sent to the remote intake
        // Default: .debug (all levels sent)
        remoteLogThreshold: .debug,

        // Print logs to console for local debugging
        // Default: nil (disabled)
        // Options: .short, .shortWith(prefix: "MyApp")
        consoleLogFormat: .short
    )
)

// 5. Log messages at various levels
logger.debug("Fetching user profile")
logger.info("User logged in", attributes: ["user.id": "abc123"])
logger.notice("Low memory warning received")
logger.warn("Retry attempt", attributes: ["attempt": 3])
logger.error("Request failed", error: someError, attributes: ["endpoint": "/v2/users"])
logger.critical("Unrecoverable state", error: someError)

// 6. Manage per-logger attributes and tags
logger.addAttribute(forKey: "screen", value: "ProductList")
logger.removeAttribute(forKey: "screen")

logger.addTag(withKey: "feature", value: "checkout")
logger.removeTag(withKey: "feature")
logger.add(tag: "beta")
logger.remove(tag: "beta")

// 7. (Optional) Set an error fingerprint on the log event
// Requires an Error to be passed; sets `error.fingerprint` on the event
logger.error(
    "Database write failed",
    error: dbError,
    attributes: [Logs.Attributes.errorFingerprint: "db-write-failure"]
)
```

## Key Files

### Feature Entry Point
- **`DatadogLogs/Sources/Logs.swift`** — Main entry point. Call `Logs.enable(with:)` to activate.
  - `addAttribute(forKey:value:)` / `removeAttribute(forKey:)` — global attributes applied to all loggers

### Configuration
- **`DatadogLogs/Sources/Logger.swift`** — `Logger.create(with:)` factory and `Logger.Configuration`.
  - Per-logger options: service, name, sampling, log threshold, console format, RUM/Trace bundling, network info

### Public API
- **`DatadogLogs/Sources/LoggerProtocol.swift`** — `LoggerProtocol` and `LogLevel` enum.
  - Logging methods: `debug`, `info`, `notice`, `warn`, `error`, `critical`
  - Attribute management: `addAttribute(forKey:value:)`, `removeAttribute(forKey:)`
  - Tag management: `addTag(withKey:value:)`, `removeTag(withKey:)`, `add(tag:)`, `remove(tag:)`

### Objective-C Bridge
- **`DatadogLogs/Sources/Logs+objc.swift`** — Objective-C entry point (`DDLogs`, `DDLoggerConfiguration`, `DDLogger`).
  - `+[DDLogs enableWith:]` mirrors Swift `Logs.enable(with:)`
  - `+[DDLogger createWith:]` mirrors Swift `Logger.create(with:)`
  - ObjC `printLogsToConsole: Bool` maps to Swift `consoleLogFormat: .short`

### Implementation
- **`DatadogLogs/Sources/Feature/`** — Internal feature implementation. Shows how configuration translates to behavior.

## Configuration Categories

### Sampling
- **Remote sampling**: `Logger.Configuration.remoteSampleRate` (default: 100%) — controls what fraction of logs are uploaded. Applied per-logger.
- **Log level filter**: `remoteLogThreshold` (default: `.debug`) — logs below this level are not sent remotely. Console output is unaffected by this threshold.

### Event Modification
- **`Logs.Configuration.eventMapper`** — `(LogEvent) -> LogEvent?`. Modify or drop log events before upload. Return `nil` to drop. Runs on a background thread; keep it fast.
- **Error fingerprint**: Set `Logs.Attributes.errorFingerprint` (`"_dd.error.fingerprint"`) as a log attribute to set `error.fingerprint` on the log event. Requires an `Error` to be passed to the log call.

### Logger Enrichment
- **Service**: `service` (default: SDK service value) — overrides `service` on log events.
- **Logger name**: `name` — reported as `logger.name` on log events.
- **Network info**: `networkInfoEnabled` (default: `false`) — attaches reachability, connection type, mobile carrier to every log.
- **RUM bundling**: `bundleWithRumEnabled` (default: `true`) — attaches `application_id`, `session_id`, `view.id`, `user_action.id` when a sampled-in RUM session is active.
- **Trace bundling**: `bundleWithTraceEnabled` (default: `true`) — attaches `dd.trace_id` and `dd.span_id` when a Datadog span is active (via `span.setActive()` from `Tracer.shared()`). OTel spans activated through `withActiveSpan` do not propagate through this path.

### Console Output
- `consoleLogFormat: nil` (default) — no console output.
- `consoleLogFormat: .short` — prints `[level] message` to the console.
- `consoleLogFormat: .shortWith(prefix: "MyApp")` — prepends a custom prefix.

### Global Attributes
Applied to all loggers in the same SDK instance:
```swift
Logs.addAttribute(forKey: "build.number", value: "42")
Logs.removeAttribute(forKey: "build.number")
```

### Per-Logger Tags and Attributes
```swift
logger.addTag(withKey: "feature", value: "checkout")  // tag: "feature:checkout"
logger.add(tag: "experiment_a")                        // bare tag
logger.addAttribute(forKey: "user.plan", value: "pro") // searchable attribute
```

## Common Troubleshooting Patterns

### "No logs appearing in Datadog"
1. Check `Datadog.initialize()` and `Logs.enable()` were called before creating loggers.
2. Verify `remoteSampleRate` is > 0.
3. Verify `remoteLogThreshold` — logs below the threshold are silently dropped before upload.
4. Check if `eventMapper` is returning `nil` for those events.

### "Some log levels not appearing"
1. `remoteLogThreshold` filters out levels below the configured minimum; only levels ≥ threshold are sent remotely.
2. Console output via `consoleLogFormat` is not affected by `remoteLogThreshold` — it always prints all levels.

### "Logs not linked to RUM session"
1. Verify `RUM.enable()` is called and a RUM session is active.
2. Verify the RUM session is sampled in — sampled-out sessions do not add RUM linkage.
3. Confirm `bundleWithRumEnabled: true` (default) on the logger.

### "Logs not linked to a trace span"
1. Verify `Trace.enable()` is called and an active span exists when logging.
2. Confirm `bundleWithTraceEnabled: true` (default) on the logger.

### "Logger.create() returns a no-op logger"
Returned when `Datadog.initialize()` was not called or `Logs.enable()` was not called. Check the console for `ProgrammerError` messages via `consolePrint`.

## Feature Interactions

- **RUM**: When `bundleWithRumEnabled` is `true` and the current RUM session is sampled in, logs are enriched with the current RUM view / session / action IDs for correlation in Datadog.
- **Trace**: When `bundleWithTraceEnabled` is `true` and an active span is present (via `Tracer.shared()` or `OTelTracerProvider`), logs are enriched with `dd.trace_id` and `dd.span_id`. Span logs written via `OTSpan.log(...)` also flow through the Logs feature — if Logs is not enabled, those span logs are dropped.

## Additional Context

- Each call to `Logger.create(with:)` returns an independent logger instance. Multiple loggers can coexist with different configurations (service, name, threshold, etc.).
- Global attributes set via `Logs.addAttribute(forKey:value:)` are merged with per-logger attributes; per-logger attributes take precedence on key conflicts.
- Tags are stored as `"key:value"` strings in the backend; bare tags (via `add(tag:)`) are stored as-is.
- `Logger.Configuration.remoteSampleRate` is applied per log event independently — unlike RUM session sampling which is decided once per session.
