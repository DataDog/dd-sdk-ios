# Codebase Structure

**Analysis Date:** 2026-02-19

## Directory Layout

```
dd-sdk-ios/
├── DatadogInternal/         # Shared protocols, types, utilities (no external dependencies)
│   ├── Sources/
│   │   ├── Attributes/              # Attribute encoding/decoding
│   │   ├── BacktraceReporting/      # Stack trace collection
│   │   ├── Codable/                 # JSON encoding utilities
│   │   ├── Concurrency/             # Thread-safety primitives (ReadWriteLock, etc.)
│   │   ├── Context/                 # DatadogContext, publishers, system info
│   │   ├── MessageBus/              # Inter-feature message passing
│   │   ├── Models/                  # RUM, Logs, Trace event models (generated from rum-events-format)
│   │   ├── NetworkInstrumentation/  # URL session swizzling for auto-instrumentation
│   │   ├── Storage/                 # FeatureStorage protocol
│   │   ├── Telemetry/               # SDK self-monitoring
│   │   ├── Upload/                  # FeatureUpload, FeatureRequestBuilder protocols
│   │   └── Utils/                   # Helpers (Date, UUID, JSON, etc.)
│   └── Tests/
│
├── DatadogCore/             # SDK initialization, data pipeline, context, network
│   ├── Sources/
│   │   ├── Datadog.swift            # SDK entry point enum
│   │   ├── DatadogConfiguration.swift # Initialization config
│   │   ├── Core/
│   │   │   ├── DatadogCore.swift          # Main orchestrator
│   │   │   ├── MessageBus.swift           # Concrete message bus
│   │   │   ├── Context/                   # Context providers (user, network, device, etc.)
│   │   │   ├── Storage/                   # File-based storage and upload pipeline
│   │   │   │   ├── Files/                 # File I/O (FilesOrchestrator, FileReader, FileWriter)
│   │   │   │   ├── Writing/               # AsyncWriter, EventGenerator
│   │   │   │   ├── Reading/               # DataReader, Reader interface
│   │   │   │   └── FeatureStorage.swift   # Storage abstraction
│   │   │   ├── Upload/                    # Batching and HTTP upload
│   │   │   │   ├── DataUploadWorker.swift # Periodic upload orchestrator
│   │   │   │   ├── DataUploader.swift     # Single batch uploader
│   │   │   │   ├── HTTPClient.swift       # HTTP abstraction
│   │   │   │   └── URLSessionClient.swift # URLSession implementation
│   │   │   ├── DataStore/                 # Key-value storage for user data
│   │   │   └── TLV/                       # Binary TLV encoding for compact storage
│   │   ├── Extensions/                  # Common extensions (String, Date, etc.)
│   │   ├── FeaturesIntegration/         # Feature registration helpers
│   │   ├── NetworkInstrumentation/      # Network auto-instrumentation
│   │   ├── SDKMetrics/                  # SDK self-monitoring
│   │   └── Utils/
│   └── Tests/
│
├── DatadogRUM/              # Real User Monitoring feature
│   ├── Sources/
│   │   ├── RUM.swift                     # RUM feature entry point
│   │   ├── RUMConfiguration.swift        # RUM config (sessionSampleRate, applicationID, etc.)
│   │   ├── RUMMonitor.swift              # Public RUMMonitor accessor
│   │   ├── RUMMonitorProtocol.swift      # Public protocol
│   │   ├── RUMMonitor/
│   │   │   ├── Monitor.swift             # Concrete RUMMonitorProtocol implementation
│   │   │   ├── RUMCommand.swift          # Command protocol and all command types
│   │   │   ├── RUMScope.swift            # Scope protocol
│   │   │   └── Scopes/
│   │   │       ├── RUMApplicationScope.swift       # Top of hierarchy
│   │   │       ├── RUMSessionScope.swift           # Session-level state
│   │   │       ├── RUMViewScope.swift              # View-level state (largest file)
│   │   │       ├── RUMResourceScope.swift          # Network resource tracking
│   │   │       ├── RUMUserActionScope.swift        # User action tracking
│   │   │       ├── RUMAppLaunchManager.swift       # App launch metrics
│   │   │       ├── RUMFeatureOperationManager.swift # Feature operation vital tracking
│   │   │       ├── RUMScopeDependencies.swift      # Dependency injection
│   │   │       └── Utils/                          # Scope helpers
│   │   ├── Feature/
│   │   │   ├── RUMFeature.swift          # Feature plugin (implements DatadogRemoteFeature)
│   │   │   ├── RequestBuilder.swift      # Build HTTP requests for upload
│   │   │   ├── RUMDataStore.swift        # Feature-specific storage
│   │   │   └── RUMViewEventsFilter.swift # Sample or filter view events
│   │   ├── RUMEvent/                     # Event command types (startView, addError, etc.)
│   │   ├── RUMMonitor/                   # (Dup of above - consolidation candidate)
│   │   ├── RUMContext/                   # RUMContext and RUMContextProvider
│   │   ├── RUMMetrics/                   # Metrics (CPU, memory, FPS)
│   │   ├── RUMVitals/                    # Vital metrics and tracking
│   │   ├── Instrumentation/
│   │   │   ├── RUMInstrumentation.swift  # Main instrumentation setup
│   │   │   ├── URLSessionInstrumentation/ # URLSession auto-instrumentation
│   │   │   ├── ViewControllerInstrumentation/ # ViewController auto-instrumentation
│   │   │   ├── GestureInstrumentation/   # User action auto-detection
│   │   │   ├── AppHangInstrumentation/   # ANR/app hang detection
│   │   │   └── etc.
│   │   ├── Integrations/                 # Integration with other features
│   │   ├── DataModels/                   # Generated RUM event models
│   │   ├── Scrubbing/                    # PII scrubbing rules
│   │   ├── SDKMetrics/                   # SDK self-monitoring
│   │   ├── UUIDs/                        # UUID generation
│   │   └── Utils/
│   └── Tests/
│
├── DatadogLogs/             # Logging feature
│   ├── Sources/
│   │   ├── Logs.swift                    # Entry point
│   │   ├── Logger.swift                  # Public Logger interface
│   │   ├── LoggerProtocol.swift          # Logger protocol
│   │   ├── RemoteLogger.swift            # Remote logger implementation
│   │   ├── Feature/                      # LogsFeature plugin
│   │   ├── Log/                          # Log event models and commands
│   │   └── Scrubbing/
│   └── Tests/
│
├── DatadogTrace/            # APM and distributed tracing feature
│   ├── Sources/
│   │   ├── Trace.swift                   # Entry point
│   │   ├── DatadogTracer.swift           # Tracer implementation
│   │   ├── Span/                         # Span models
│   │   ├── OpenTelemetry/                # OpenTelemetry API implementation
│   │   ├── OpenTracing/                  # OpenTracing API compatibility
│   │   ├── Feature/                      # TraceFeature plugin
│   │   ├── Integrations/                 # Integration with URLSession, etc.
│   │   └── Scrubbing/
│   └── Tests/
│
├── DatadogSessionReplay/    # Session recording feature
│   ├── Sources/
│   │   ├── SessionReplay.swift           # Entry point
│   │   ├── SessionReplayConfiguration.swift
│   │   ├── Feature/                      # SessionReplayFeature plugin
│   │   ├── Recorder/                     # View tree capture
│   │   ├── Processor/                    # Record processing and compression
│   │   ├── Writers/                      # Event serialization
│   │   ├── Models/                       # Generated session replay models
│   │   └── Utilities/
│   ├── Tests/
│   └── SRSnapshotTests/                  # Visual regression tests (snapshots)
│
├── DatadogCrashReporting/   # Crash detection and reporting
│   ├── Sources/
│   │   ├── CrashReporting.swift          # Entry point
│   │   ├── Feature/                      # CrashReportingFeature plugin
│   │   └── (Uses PLCrashReporter)
│   └── Tests/
│
├── DatadogWebViewTracking/  # WebView-to-mobile RUM session linkage
│   ├── Sources/
│   │   ├── WebViewTracking.swift         # Entry point
│   │   └── (Bridges WebView RUM to native RUM)
│   └── Tests/
│
├── DatadogFlags/            # Feature flags
│   ├── Sources/
│   │   ├── Flags.swift                   # Entry point
│   │   ├── Client/                       # Feature flags client
│   │   └── Models/
│   └── Tests/
│
├── DatadogProfiling/        # Continuous profiling (internal)
│   ├── Sources/
│   │   ├── Protos/                       # Protobuf models
│   │   ├── Mach/                         # Low-level profiling primitives
│   │   └── (Sampling-based CPU/memory)
│   └── Tests/
│
├── TestUtilities/           # Shared testing infrastructure
│   └── Sources/
│       ├── Mocks/                        # Mock implementations of core protocols
│       ├── Fakes/                        # Fake implementations (e.g., FakeDateProvider)
│       ├── DatadogCoreProxy.swift        # In-memory SDK instance for tests
│       └── Helpers/                      # Test data factories
│
├── IntegrationTests/        # UI and integration tests (CocoaPods-based)
│   ├── IntegrationScenarios/   # Test scenarios
│   ├── Runner/                  # Test runner app
│   └── IntegrationTests.xcworkspace
│
├── E2ETests/                # End-to-end tests (real backend)
│   ├── Runner/                  # Test runner app
│   └── (Run nightly against real Datadog backend)
│
├── BenchmarkTests/          # Performance benchmarks
│   ├── Runner/
│   ├── Benchmarks/
│   ├── CatalogSwiftUI/       # SwiftUI catalog app
│   └── CatalogUIKit/         # UIKit catalog app
│
├── SmokeTests/              # Integration smoke tests
│   ├── spm/                 # Swift Package Manager integration
│   ├── cocoapods/           # CocoaPods integration
│   ├── carthage/            # Carthage integration
│   └── xcframeworks/        # XCFramework distribution
│
├── Datadog.xcworkspace      # Main workspace
│
├── Datadog/                 # Xcode project
│   ├── Example/             # Example app (sandbox for testing)
│   ├── Datadog.xcodeproj
│   └── IntegrationUnitTests/
│
├── xcconfigs/               # Xcode build configurations
│
├── tools/                   # Build and maintenance tools
│   ├── rum-models-generator/   # Generate RUM models from rum-events-format
│   ├── sr-snapshots/           # Session Replay snapshot management
│   ├── api-surface/            # Verify API surface hasn't changed
│   ├── lint/                    # SwiftLint wrapper with custom rules
│   ├── license/                 # License header validation
│   ├── repo-setup/              # Initial repo setup
│   ├── release/                 # Release automation
│   ├── http-server-mock/        # Mock HTTP server for testing
│   ├── xcode-templates/         # Xcode file templates
│   └── utils/
│
├── docs/                    # Documentation
│   ├── specs/               # Feature specifications
│   ├── sdk_performance.md   # Performance guidelines
│   └── session_replay_performance.md
│
├── .planning/               # GSD milestone artifacts
│   └── codebase/           # Codebase analysis documents
│
├── CLAUDE.md                # Claude Code instructions
├── AGENTS.md                # AI agent guidelines
├── ZEN.md                   # SDK philosophy
├── CONTRIBUTING.md          # Contribution guidelines
├── CHANGELOG.md             # Release notes
└── api-surface-swift        # Auto-generated API surface (for CI)
```

## Directory Purposes

**DatadogInternal:**
- Purpose: Shared internal infrastructure used by all features
- Contains: Protocols (`DatadogFeature`, `FeatureStorage`, `FeatureUpload`), generated event models, context providers
- Key files: `DatadogCoreProtocol.swift`, `DatadogFeature.swift`, `Context/`, `Models/`, `MessageBus/`

**DatadogCore:**
- Purpose: SDK initialization, data pipeline (storage → batching → upload), context management
- Contains: Datadog public API entry point, core orchestrator, storage/upload machinery, HTTP client, context providers
- Key files: `Datadog.swift`, `Core/DatadogCore.swift`, `Core/Storage/`, `Core/Upload/`

**DatadogRUM:**
- Purpose: Real User Monitoring event collection
- Contains: Public RUMMonitor API, scope hierarchy (Application/Session/View), instrumentation hooks, event models
- Key files: `RUMMonitor.swift`, `RUMMonitorProtocol.swift`, `RUMMonitor/Monitor.swift`, `RUMMonitor/Scopes/`

**DatadogLogs, DatadogTrace, etc.:**
- Purpose: Feature-specific functionality
- Contains: Public API, feature plugin, event models, instrumentation if applicable
- Key files: `{Feature}.swift` (entry point), `Feature/{Feature}Feature.swift` (plugin)

**TestUtilities:**
- Purpose: Shared test mocks and helpers
- Contains: DatadogCoreProxy (fake in-memory SDK), mock objects for protocols
- Key files: `DatadogCoreProxy.swift`, `Mocks/`, `Fakes/`

**IntegrationTests:**
- Purpose: UI and integration testing
- Contains: Test scenarios, test runner app
- Key files: `IntegrationScenarios/`, `Runner/`

## Key File Locations

**Entry Points:**
- `DatadogCore/Sources/Datadog.swift`: SDK initialization
- `DatadogRUM/Sources/RUMMonitor.swift`: RUM public API
- `DatadogLogs/Sources/Logs.swift`: Logs feature initialization
- `DatadogTrace/Sources/Trace.swift`: Tracing feature initialization

**Configuration:**
- `DatadogCore/Sources/DatadogConfiguration.swift`: Core SDK config
- `DatadogRUM/Sources/RUMConfiguration.swift`: RUM config
- `DatadogTrace/Sources/TraceConfiguration.swift`: Trace config
- `DatadogSessionReplay/Sources/SessionReplayConfiguration.swift`: Session Replay config

**Core Logic:**
- `DatadogCore/Sources/Core/DatadogCore.swift`: Feature registry and orchestration
- `DatadogRUM/Sources/RUMMonitor/Monitor.swift`: RUM monitor implementation
- `DatadogRUM/Sources/RUMMonitor/Scopes/RUMViewScope.swift`: View-level RUM logic (largest file)
- `DatadogCore/Sources/Core/Storage/FilesOrchestrator.swift`: File storage orchestration
- `DatadogCore/Sources/Core/Upload/DataUploadWorker.swift`: Upload worker loop

**Testing:**
- `TestUtilities/Sources/DatadogCoreProxy.swift`: Fake SDK for unit tests
- `DatadogRUM/Tests/`: RUM unit tests
- `IntegrationTests/Runner/`: Integration test runner
- `E2ETests/Runner/`: End-to-end test runner

## Naming Conventions

**Files:**
- Feature public API: `{Feature}.swift` (e.g., `RUM.swift`, `Logs.swift`)
- Feature configuration: `{Feature}Configuration.swift`
- Feature implementation: `{Feature}Feature.swift` (in `Feature/` subdirectory)
- Scope files: `RUM{ScopeName}Scope.swift` (e.g., `RUMApplicationScope.swift`)
- Command types: Included in `RUMCommand.swift` (large struct enum)
- Monitor/client: `Monitor.swift` or `{Feature}Client.swift`
- Protocols: `{Feature}Protocol.swift`

**Directories:**
- Feature submodules: Datadog{Feature} (e.g., DatadogRUM)
- Scope hierarchy: `RUMMonitor/Scopes/`
- Feature plugin: `Feature/`
- Instrumentation: `Instrumentation/`
- Models: `DataModels/` or `Models/`
- Tests: `Tests/` at module level

## Where to Add New Code

**New Feature Module (e.g., DatadogNotifications):**
1. Create `/Users/valentin.pertuisot/work/cross-sdk-project/dd-sdk-ios/DatadogNotifications/` directory
2. Create `Sources/` subdirectory with module structure:
   - `Notifications.swift` (entry point)
   - `NotificationsConfiguration.swift` (config)
   - `Feature/NotificationsFeature.swift` (plugin, implements `DatadogRemoteFeature`)
   - `NotificationsMonitor.swift` (public interface)
3. Create `Tests/` subdirectory with unit tests
4. Update `Datadog.xcworkspace` to include new target
5. Add to `tools/rum-models-generator/` if event models needed
6. Update `AGENTS.md` section "Where to implement feature logic"

**New RUM Instrumentation (e.g., gesture handling):**
1. Create file in `DatadogRUM/Sources/Instrumentation/GestureInstrumentation/`
2. Follow pattern of existing instrumentation (e.g., `URLSessionInstrumentation/`)
3. Register in `RUMInstrumentation.swift` `init()` method
4. Add unit tests in `DatadogRUM/Tests/RUMTests/Instrumentation/`

**New RUM Command:**
1. Add struct to `DatadogRUM/Sources/RUMMonitor/RUMCommand.swift`
2. Implement `RUMCommand` protocol
3. Add processing logic in appropriate scope (`RUMApplicationScope`, `RUMSessionScope`, etc.)
4. Add tests in `DatadogRUM/Tests/RUMTests/Scopes/`

**New Context Provider (e.g., ThermalState):**
1. Create file in `DatadogCore/Sources/Core/Context/ThermalStatePublisher.swift`
2. Implement `ContextValuePublisher` protocol
3. Subscribe to system notifications (e.g., `NSProcessInfoThermalStateDidChangeNotification`)
4. Add to `DatadogContextProvider.swift` `init()`
5. Add unit tests in `DatadogCore/Tests/`

**Shared Internal Types (used by multiple features):**
1. Add to `DatadogInternal/Sources/` in appropriate subdirectory (e.g., `Attributes/`, `Codable/`, `Context/`)
2. Example: new attribute type would go in `DatadogInternal/Sources/Attributes/`
3. Add unit tests in `DatadogInternal/Tests/`

## Special Directories

**DatadogInternal/Sources/Models/:**
- Purpose: Auto-generated RUM, Logs, Trace, SessionReplay event models
- Generated: Yes (from https://github.com/DataDog/rum-events-format)
- Committed: Yes
- Tool: `tools/rum-models-generator/` (reads `.json` schemas, outputs Swift code)
- Regenerate: `make rum-models-generate GIT_REF=master`

**tools/**
- Purpose: Build, code generation, linting, release automation
- Generated: No
- Committed: Yes
- Notable:
  - `rum-models-generator/`: Python script to generate RUM models from JSON schemas
  - `api-surface/`: Extracts and verifies public API (prevents unintended API changes)
  - `lint/`: SwiftLint wrapper with custom rules (e.g., ensure tests use mocks, not real network)
  - `release/`: Automation for releasing new versions

**IntegrationTests/xctestplans/**
- Purpose: Define test plans for UI integration tests
- Generated: No
- Committed: Yes
- Files define which tests run in CI, which are skipped, etc.

**docs/specs/**
- Purpose: Feature specifications and design documents
- Generated: No
- Committed: Yes
- Examples: `DatadogRUM/RUM_FEATURE.md`, `DatadogSessionReplay/SESSION_REPLAY_FEATURE.md`

**.planning/codebase/**
- Purpose: GSD-generated codebase analysis documents
- Generated: Yes (by `/gsd:map-codebase`)
- Committed: Yes

---

*Structure analysis: 2026-02-19*
