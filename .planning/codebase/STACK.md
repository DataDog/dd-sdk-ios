# Technology Stack

**Analysis Date:** 2026-02-19

## Languages

**Primary:**
- Swift 5.9 - Core SDK implementation across all modules
- Objective-C - Bridge code and private C APIs (DatadogCore/Private, URLSessionInstrumentation)
- C++ 17 - Profiling infrastructure (DatadogProfiling/Mach)
- C - Low-level crash handling (via KSCrash dependency)

**Secondary:**
- BrightScript/BrighterScript - Roku SDK (separate repo)
- Python - Build tooling and code generation (rum-models-generator)

## Runtime

**Environment:**
- Apple platforms: iOS 12+, tvOS 12+, watchOS 7+, macOS 12+, visionOS (selected modules)
- Xcode 15+ recommended

**Package Manager:**
- SPM (Swift Package Manager) - Primary distribution mechanism
- CocoaPods - Alternative package manager support
- Carthage - Alternative distribution method
- XCFrameworks - Binary distribution support

## Frameworks

**Core SDK Architecture:**
- DatadogCore - Base SDK initialization, configuration, storage, upload, and message bus
- DatadogInternal - Shared internal utilities, protocols, context, upload infrastructure
- DatadogLogs - Log collection and transmission
- DatadogTrace - Distributed tracing with OpenTelemetry API support
- DatadogRUM - Real User Monitoring events collection
- DatadogSessionReplay - Session replay recording and processing
- DatadogCrashReporting - Crash detection and reporting
- DatadogWebViewTracking - WebView instrumentation
- DatadogFlags - Feature flags evaluation and exposure logging
- DatadogProfiling - Profiling data collection

**Testing:**
- XCTest - Native iOS unit test framework
- Swift Testing - Modern Swift test framework (when available)

**Build/Dev:**
- SPM for package definitions
- Xcode build system
- Make - Build automation (see Makefile)
- CocoaPods - Pod specification files (.podspec)
- Carthage - Binary dependency management

## Key Dependencies

**Critical:**
- opentelemetry-swift-core v2.3.0+ - OpenTelemetry API for distributed tracing (DatadogTrace)
  - Provides OpenTelemetryApi product for span/trace creation
  - URL: https://github.com/open-telemetry/opentelemetry-swift-core
- KSCrash 2.5.0 - Crash detection and reporting (DatadogCrashReporting)
  - Products: Recording (crash detection), Filters (report processing)
  - URL: https://github.com/kstenerud/KSCrash.git

**Internal:**
- DatadogInternal - Shared protocols and utilities for cross-module communication
- TestUtilities - Mocks, fixtures, and test helpers (not exported by default, enabled via DD_TEST_UTILITIES_ENABLED env)

**OpenTelemetry:**
- Default: Lightweight OpenTelemetry API mirror
- Alternate: Full OpenTelemetry SDK via OTEL_SWIFT environment variable

## Configuration

**Environment:**
- Initialized via `Datadog.initialize(with:trackingConsent:)` with a Configuration struct
- Client token or RUM client token required (passed in configuration)
- Site selection: `.us1` (default), `.us3`, `.us5`, `.eu1`, `.ap1`, `.ap2`, `.us1_fed`
- Custom proxy configuration supported via URLSessionConfiguration
- Optional data encryption via DataEncryption protocol implementation

**Build:**
- Package.swift - SPM manifest with modular targets
- Podfiles and .podspec files - CocoaPods integration
- Cartfile - Carthage dependencies (minimal, only OpenTelemetryApi.json)
- xcconfigs/ directory - Xcode build settings
- .xcodeprojfiles - Generated project configuration

**Storage:**
- File-based persistent storage in application sandbox
- FeatureDataStore for key-value data storage
- FilesOrchestrator manages file reading/writing
- Directory structure: `[AppSupport]/Datadog/[site]/[feature]/`
- Optional encryption layer for on-disk data (DataEncryption protocol)
- No database (SQLite/CoreData) - uses filesystem directly

## Platform Requirements

**Development:**
- Xcode 15+ recommended (16+ for Swift 6 formatting)
- macOS 12+ for building
- Mise for tool version management (optional, used for Tuist and other tools)

**Production:**
- iOS: 12.0+
- tvOS: 12.0+
- watchOS: 7.0+ (DatadogCore, DatadogLogs, DatadogTrace only)
- macOS: 12.0+ (most modules, Catalyst supported)
- visionOS: Supported for most modules

**Network:**
- HTTPS only (browser-intake-datadoghq.com and regional variants)
- URL session configuration: ephemeral, no caching (RUMM-610)
- Proxy support via connectionProxyDictionary
- Multipart form data for batch uploads
- Gzip compression support

**Permissions:**
- FileManager access to Application Support directory
- URLSession for network requests
- UserDefaults for persisting some state (secondary to filesystem)
- CFProxyUsernameKey/CFProxyPasswordKey for proxy authentication

## Special Build Configurations

**Benchmarking:**
- DD_BENCHMARK environment variable enables benchmark builds
- Defines DD_BENCHMARK swift setting in Package.swift

**Testing:**
- DD_TEST_UTILITIES_ENABLED exports TestUtilities library for integration testing
- DD_TEST_SCENARIO_CLASS_NAME, DD_TEST_SERVER_MOCK_CONFIGURATION for UI tests
- DD_SESSION_TYPE override for RUM session type testing

---

*Stack analysis: 2026-02-19*
