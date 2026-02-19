# External Integrations

**Analysis Date:** 2026-02-19

## APIs & External Services

**Datadog Backend:**
- Logs API - Event collection via `DatadogLogs` module
  - SDK: Built-in URLSessionClient
  - Auth: Client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

- RUM (Real User Monitoring) API - User session and event tracking via `DatadogRUM` module
  - SDK: Built-in URLSessionClient with multipart form data
  - Auth: RUM client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

- APM (Application Performance Monitoring) API - Trace collection via `DatadogTrace` module
  - SDK: Built-in URLSessionClient
  - Auth: Client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

- Session Replay API - Session recording via `DatadogSessionReplay` module
  - SDK: Built-in URLSessionClient with multipart form data
  - Auth: RUM client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

- Crash Reporting API - Crash event transmission via `DatadogCrashReporting` module
  - SDK: Built-in URLSessionClient
  - Auth: Client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

- Feature Flags API - Flag assignments fetching and exposure logging via `DatadogFlags` module
  - SDK: Built-in URLSessionClient
  - Auth: RUM client token (DD-API-KEY header)
  - Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

## Data Storage

**Databases:**
- File-based storage (no relational database)
  - Type: Filesystem (Application Support directory)
  - Directory structure: `[AppSupport]/Datadog/[site]/[feature]/`
  - Client: FileManager (standard Foundation)
  - Format: JSON for events, binary for compressed payloads
  - Encryption: Optional via DataEncryption protocol in `DatadogCore/Sources/Core/Storage/DataEncryption.swift`

**File Storage:**
- Local filesystem only (Application Support sandbox)
- Batched event files managed by FilesOrchestrator
- Storage at `DatadogCore/Sources/Core/Storage/`

**Caching:**
- None at URLSession level (explicitly disabled - RUMM-610)
- URLSessionConfiguration.urlCache = nil
- Location: `DatadogCore/Sources/Core/Upload/URLSessionClient.swift`

## Authentication & Identity

**Auth Provider:**
- Custom token-based authentication (no OAuth/third-party auth provider)

**Implementation:**
- Client Token required during SDK initialization
- Token passed in DD-API-KEY HTTP header for all requests
- Supported tokens: Regular client token or RUM client token
- Header building: `URLRequestBuilder.ddAPIKeyHeader(clientToken:)`
- Location: `DatadogInternal/Sources/Upload/URLRequestBuilder.swift`

## Monitoring & Observability

**Error Tracking:**
- KSCrash integration for native crash detection and reporting
  - Library: KSCrash 2.5.0 (Recording and Filters products)
  - Products: Recording (crash detection), Filters (report processing)
  - URL: https://github.com/kstenerud/KSCrash.git
  - Location: `DatadogCrashReporting/Sources/`

**Logs:**
- Internal logging via DD.logger (InternalLogger)
- Errors logged to internal telemetry system
- Location: `DatadogInternal/Sources/` and feature-specific implementations

**Telemetry:**
- SDK metrics tracking (upload quality, errors)
- Location: `DatadogCore/Sources/SDKMetrics/`

## CI/CD & Deployment

**Hosting:**
- GitHub-hosted repository
- GitHub Actions for CI
- Deployment: CocoaPods, SPM, Carthage, XCFrameworks

**CI Pipeline:**
- `.gitlab-ci.yml` - GitLab CI configuration (main pipeline)
- `.github/` - GitHub Actions workflows
- Test schemes: iOS unit tests, tvOS unit tests, UI integration tests, smoke tests, snapshot tests
- Coverage: Enabled for CI runs
- Automated model generation from rum-events-format schema

## Environment Configuration

**Required env vars:**
- SDK_TRACKING_CONSENT - App tracking consent level (default: .granted, can be .pending, .notGranted)
- DD_SESSION_TYPE - Override session type for testing (optional, RUM)

**Configuration at initialization:**
- clientToken - API authentication token (required)
- env - Environment name (staging, production, etc.)
- service - Service name (default: bundle identifier)
- version - App version (default: Info.plist CFBundleShortVersionString or CFBundleVersion)
- site - Datadog site (.us1, .us3, .us5, .eu1, .ap1, .ap2, .us1_fed)
- batchSize - Data batch size preference (.small, .medium, .large)
- uploadFrequency - Upload frequency (.frequent, .average, .rare)
- proxyConfiguration - Custom proxy settings for URLSession
- encryption - Optional data encryption implementation

**Secrets location:**
- Client token: Passed via Configuration struct during initialization
- Not stored in code or committed to repository
- Should be injected at app build/runtime

**Build-time env vars:**
- DD_BENCHMARK - Enables benchmark mode (Swift setting)
- DD_TEST_UTILITIES_ENABLED - Exports TestUtilities library
- OTEL_SWIFT - Use full OpenTelemetry SDK (default: lightweight API mirror)

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- Session Replay API - Records user session interactions
- RUM API - Sends view transitions, user actions, errors
- APM API - Sends trace spans
- Crash Reporting API - Sends crash reports after next app launch
- Logs API - Sends application logs
- Feature Flags API - Sends flag evaluations and exposures

## Request & Response Handling

**HTTP Headers (Custom):**
- `DD-API-KEY` - Client token for authentication
- `DD-EVP-ORIGIN` - Request origin tracking (SDK identifier)
- `DD-EVP-ORIGIN-VERSION` - SDK version for observability
- `DD-REQUEST-ID` - Optional request ID for debugging (UUID)
- `DD-IDEMPOTENCY-KEY` - Optional idempotency key
- `User-Agent` - Sanitized app name, version, device info
- `Content-Type` - application/json or multipart/form-data
- `Content-Encoding` - gzip for compressed payloads

**Upload Formats:**
- JSON for single event payloads
- NDJSON (newline-delimited JSON) for batches
- Multipart form-data for file uploads (session replay, crashes)
- Gzip compression supported

**Endpoints by Site:**
- `.us1` → https://browser-intake-datadoghq.com/
- `.us3` → https://browser-intake-us3-datadoghq.com/
- `.us5` → https://browser-intake-us5-datadoghq.com/
- `.eu1` → https://browser-intake-datadoghq.eu/
- `.ap1` → https://browser-intake-ap1-datadoghq.com/
- `.ap2` → https://browser-intake-ap2-datadoghq.com/
- `.us1_fed` → https://browser-intake-ddog-gov.com/

**Location:** `DatadogInternal/Sources/Context/DatadogSite.swift`

## Third-Party Libraries

**OpenTelemetry Integration:**
- opentelemetry-swift-core 2.3.0+
  - Products: OpenTelemetryApi (public), OpenTelemetrySdk (optional)
  - Optional full SDK via OTEL_SWIFT environment variable
  - Used by DatadogTrace for APM span creation

**Message Bus:**
- Inter-module communication via MessageBusReceiver protocol
- Features subscribe to messages from other features (cross-module events)
- Location: `DatadogInternal/Sources/`

---

*Integration audit: 2026-02-19*
