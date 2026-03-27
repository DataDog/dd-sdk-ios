# SDK Architecture

## Module Structure

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

### Module Boundaries

- Feature modules MUST NOT import each other
- Only `DatadogCore` orchestrates feature lifecycles
- `DatadogInternal` is the ONLY allowed place for shared types — it defines interfaces; `DatadogCore` provides concrete implementations
- Platform support: iOS 12.0+, tvOS 12.0+, macOS 12.6+, watchOS 7.0+ (limited modules), visionOS

### Call Site Synchronization

**When modifying code in feature modules (Logs, Trace, RUM, etc.), you MUST check if any corresponding call sites in `DatadogCore` and `DatadogInternal` need to be updated.**

Common oversights:
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

- **Datadog Integration for Apollo iOS**: https://github.com/DataDog/dd-sdk-ios-apollo-interceptor — extracts GraphQL Operation information from requests to let DatadogRUM enrich GraphQL RUM Resources
