---
last_updated: 2026-08-04
sdk_version: 3.14.0
verified_against_commit: cc8c93bb3
tracked_files:
  - DatadogRUM/Sources/RUM.swift
  - DatadogRUM/Sources/RUMConfiguration.swift
  - DatadogRUM/Sources/RUMMonitor.swift
  - DatadogRUM/Sources/RUMMonitorProtocol.swift
---

# RUM (Real User Monitoring) Feature

## Overview

RUM tracks user interactions, views, resources, errors, and performance metrics in iOS applications. It requires initialization via `Datadog.initialize()` before enabling.

**Platform**: iOS, tvOS, watchOS, visionOS — with platform-specific limitations:
- **iOS / visionOS**: Full feature set.
- **tvOS**: UIKit and SwiftUI view tracking, UIKit action tracking (press-based), app hangs, long tasks, vitals, slow frames, memory warnings, watchdog terminations. No `swiftUIActionsPredicate` (tap-gesture path), no scroll/swipe tracking.
- **watchOS**: No automatic view/action tracking predicates (UIKit and SwiftUI), no memory warnings. URLSession tracking, event mappers, manual RUM instrumentation, session callbacks, and CPU/memory vitals are available. Refresh-rate and slow-frame data are unavailable (no DisplayLink on watchOS).

## Quick Start Example

```swift
import DatadogCore
import DatadogRUM

// 1. Initialize Core SDK first
Datadog.initialize(
    with: Datadog.Configuration(
        clientToken: "<client_token>",
        env: "<environment>"
    ),
    trackingConsent: .granted
)

// 2. Configure and enable RUM
RUM.enable(
    with: RUM.Configuration(
        applicationID: "<rum_application_id>",
        
        // Session sampling: 100 = all sessions tracked, 0 = none tracked
        // Default: 100.0
        sessionSampleRate: 100.0,
        
        // UIKit automatic view tracking - provide predicate to enable
        // Default: nil (disabled)
        // Or use custom: MyCustomViewsPredicate()
        uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
        
        // UIKit automatic action tracking - provide predicate to enable
        // Default: nil (disabled)
        // Or use custom: MyCustomActionsPredicate()
        uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate(),
        
        // SwiftUI automatic view tracking - provide predicate to enable
        // Default: nil (disabled)
        // Or use custom: MyCustomViewsPredicate()
        // Note: Also requires uiKitViewsPredicate for SwiftUI tracking to work correctly
        // Note: Experimental API - may change in future releases
        swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
        
        // SwiftUI automatic action tracking - provide predicate to enable
        // Default: nil (disabled)
        // Or use custom: MyCustomActionsPredicate()
        // Note: Also requires uiKitActionsPredicate for SwiftUI tracking to work correctly
        // Note: Experimental API - behavior differs between iOS 17 and below vs iOS 18+
        swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
        
        // Automatic network resource tracking - provide config to enable
        // Default: nil (disabled)
        urlSessionTracking: RUM.Configuration.URLSessionTracking(
            // Optional: Enable distributed tracing for first-party hosts
            firstPartyHostsTracing: .trace(
                hosts: ["api.example.com", "example.com"],
                sampleRate: 100.0
            ),
            // Optional: Add custom attributes to resources.
            // Note: in registered-delegate mode (enableDurationBreakdown), `data` is:
            //   - nil for media types (image/*, video/*, audio/*, application/octet-stream)
            //   - nil for responses over 512 KB (all other types)
            resourceAttributesProvider: { request, response, data, error in
                return ["custom.attribute": "value"]
            },
            // Optional: Capture HTTP headers from requests and responses
            // Default: .disabled
            // Options:
            //   .disabled - No header capture
            //   .defaults - Capture predefined common headers (cache-control, content-type, etag, etc.)
            //   .custom([rules]) - Capture headers by custom rules
            trackResourceHeaders: .defaults
        ),
        
        // Track user frustrations (error taps following errors)
        // Default: true
        trackFrustrations: true,
        
        // Track events when no view is active (creates background view)
        // Default: false
        // Warning: May increase session count and billing
        trackBackgroundEvents: false,
        
        // Long task threshold: report tasks on main thread exceeding duration
        // Default: 0.1 (100ms)
        // Set to nil or 0 to disable
        longTaskThreshold: 0.1,
        
        // App hang threshold: report hangs exceeding duration
        // Default: nil (disabled)
        // Minimum: 0.1 seconds
        // Requires Crash Reporting for stack traces
        appHangThreshold: 2.0,
        
        // Track watchdog terminations as RUM errors
        // Default: false
        trackWatchdogTerminations: false,
        
        // Mobile vitals collection frequency
        // Default: .average
        // Options: .frequent (100ms), .average (500ms), .rare (1000ms), or nil (disabled)
        vitalsUpdateFrequency: .average,
        
        // Time-to-Network-Settled predicate: classify resources for TNS metric
        // Default: TimeBasedTNSResourcePredicate() (resources within 100ms of view start)
        networkSettledResourcePredicate: TimeBasedTNSResourcePredicate(threshold: 0.1),
        
        // Interaction-to-Next-View predicate: classify last interaction for INV metric
        // Default: TimeBasedINVActionPredicate() (actions within 3s of next view)
        // Set to nil to disable INV metric
        nextViewActionPredicate: TimeBasedINVActionPredicate(maxTimeToNextView: 3.0),
        
        // Event mappers: modify events before sending
        // viewEventMapper can modify but NOT drop views (non-optional return)
        viewEventMapper: { viewEvent in
            var modified = viewEvent
            // Modify view event
            return modified
        },
        
        // Other event mappers can drop events by returning nil
        resourceEventMapper: { resourceEvent in
            var modified = resourceEvent
            // Scrub sensitive data
            modified.resource.url = scrubURL(modified.resource.url)
            return modified // or return nil to drop
        },
        // Also available: errorEventMapper, actionEventMapper, longTaskEventMapper
        
        // Session start callback
        // Note: this is a `@Sendable` closure (SessionListener) — it may be
        // invoked from a background queue, so only capture Sendable state.
        onSessionStart: { sessionId, isDiscarded in
            // `sessionId` matches the emitted RUM event `session.id`
            print("Session \(sessionId) started, sampled out: \(isDiscarded)")
        },
        
        // Custom RUM intake endpoint
        // Default: nil (uses Datadog intake)
        customEndpoint: nil,
        
        // Track anonymous user ID across sessions
        // Default: true
        trackAnonymousUser: true,
        
        // Track memory warnings as RUM errors
        // Default: true
        trackMemoryWarnings: true,
        
        // Track slow frames / view hitches
        // Default: true
        trackSlowFrames: true,
        
        // SDK telemetry sampling rate (for Datadog internal monitoring)
        // Default: 20.0
        telemetrySampleRate: 20.0,
        
        // Collect accessibility settings in view events
        // Default: false
        collectAccessibility: false,
        
        // RUM feature flags
        // Default: .defaults ([.trackScrollAndSwipeActions: true])
        // Set [.trackScrollAndSwipeActions: false] to disable automatic
        // scroll/swipe action tracking and INV attribution for those gestures
        featureFlags: .defaults
    )
)

// 3. (Optional) Enable duration breakdown for detailed timing data
// This must be called AFTER RUM.enable()
URLSessionInstrumentation.enableDurationBreakdown(
    with: .init(delegateClass: CustomURLSessionDelegate.self)
)

// 4. Use RUM Monitor for manual tracking
let monitor = RUMMonitor.shared()

// Start a view
monitor.startView(key: "ProductList", name: "Product List Screen")

// Add custom error
monitor.addError(message: "Failed to load products", source: .network)

// Read the active sampled-in session ID, matching emitted RUM event `session.id`
monitor.currentSessionID { sessionId in
    print("Current RUM session: \(sessionId ?? "none")")
}

// Stop the view
monitor.stopView(key: "ProductList")
```

## Key Files

### Feature Entry Point
- **`DatadogRUM/Sources/RUM.swift`** - Main entry point. Call `RUM.enable(with:)` to activate the feature.

### Configuration
- **`DatadogRUM/Sources/RUMConfiguration.swift`** - All configuration options available to customers.
  - Defines what can be tracked (views, actions, resources, errors)
  - Sampling rates and performance options
  - Event mappers and callbacks
  - Check this file to understand what customers can configure

### Public API
- **`DatadogRUM/Sources/RUMMonitor.swift`** - Access point for manual RUM tracking via `RUMMonitor.shared()`
- **`DatadogRUM/Sources/RUMMonitorProtocol.swift`** - Full API for manual RUM instrumentation
  - Views: `startView()`, `stopView()`
  - Errors: `addError()`; sources are `.source`, `.network`, `.webview`, `.console`, `.logger`, and `.custom`
  - Resources: `startResource()`, `stopResource()`
  - Actions: `addAction()`, `startAction()`, `stopAction()`
  - Current session ID, custom attributes, timings, and feature flags

### Implementation
- **`DatadogRUM/Sources/Feature/RUMFeature.swift`** - Internal feature implementation. Shows how configuration translates to behavior.

## Configuration Categories

### Automatic Tracking
Requires configuration to be set, otherwise disabled by default:
- **View tracking**: `uiKitViewsPredicate`, `swiftUIViewsPredicate` *(SwiftUI: experimental)*
- **Action tracking**: `uiKitActionsPredicate`, `swiftUIActionsPredicate` *(SwiftUI: experimental, behavior differs on iOS 17 vs iOS 18+)*
- **Resource tracking**: `urlSessionTracking` (automatic), optionally call `URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: YourSessionDelegate.self))` for detailed timing
- **Header capture**: `urlSessionTracking.trackResourceHeaders` — `.disabled` (default), `.defaults` (common headers), or `.custom([rules])`

### Performance Monitoring
- **Long tasks**: `longTaskThreshold` (default: 0.1s)
- **App hangs**: `appHangThreshold` (default: nil/disabled)
- **Vitals**: `vitalsUpdateFrequency` (default: .average)
- **Slow frames**: `trackSlowFrames` (default: true) — captures view hitches and attaches them to the corresponding RUM view

### Sampling
- **Sessions**: `sessionSampleRate` (default: 100%)
- **Telemetry**: `telemetrySampleRate` (default: 20%)

### Event Modification
Event mappers allow modifying or dropping events before upload:
- `viewEventMapper` - Modify views only (cannot return `nil` - views cannot be dropped)
- `resourceEventMapper` - Modify or drop resource events (can return `nil`)
- `errorEventMapper` - Modify or drop error events (can return `nil`)
- `actionEventMapper` - Modify or drop action events (can return `nil`)
- `longTaskEventMapper` - Modify or drop long task events (can return `nil`)

**Note**: To filter views, use view predicates instead of the mapper.

### Feature Flags
- `featureFlags` defaults to `.defaults`, currently `[.trackScrollAndSwipeActions: true]`.
- `.trackScrollAndSwipeActions`: when set to `false`, disables automatic scroll and swipe action tracking done through `UIScrollView.delegate` swizzling. It has no effect unless `uiKitActionsPredicate` is configured. Disabling it also prevents scroll/swipe gestures from being considered for INV (Interaction-to-Next-View) attribution.
- `.none`: no-op feature flag case kept in the public enum.

## Common Troubleshooting Patterns

### "No RUM data appearing"
1. Check `Datadog.initialize()` and `RUM.enable()` were called
2. Verify session wasn't sampled out (check `sessionSampleRate`)
3. `currentSessionID(completion:)` returns `nil` when there is no active session or the active session is sampled out

### "Views or actions not tracked"
1. Check if predicates are configured in RUMConfiguration
2. For UIKit: `uiKitViewsPredicate` and `uiKitActionsPredicate` must be set
3. For SwiftUI: `swiftUIViewsPredicate` and `swiftUIActionsPredicate` must be set, as well as UIKit predicates
4. If scroll/swipe actions are missing while taps still appear, check `featureFlags[.trackScrollAndSwipeActions]`; setting it to `false` disables those automatic actions and their INV attribution

### "Network requests not tracked"
1. Verify `urlSessionTracking` is configured in RUMConfiguration (RUM.enable() handles URLSessionInstrumentation internally)
2. Network requests are automatically tracked without additional configuration
3. For detailed timing breakdown (DNS, SSL, TTFB), call `URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: YourSessionDelegate.self))` after RUM has been enabled

### "Some events missing"
1. Check if event mappers are configured - `resourceEventMapper`, `errorEventMapper`, `actionEventMapper`, `longTaskEventMapper` can drop events by returning `nil`
2. Note: `viewEventMapper` cannot drop views - use predicates to filter views instead
3. Ensure each RUM event (error, resource, action) is associated with an active view - events without views are dropped

## Feature Interactions

- **Crash Reporting**: Enhances App Hang monitoring with stack traces
- **Tracing**: Network resources can create distributed traces via `firstPartyHostsTracing`
- **Session Replay**: RUM must be enabled for Session Replay to work
- **WebView Tracking**: Enables RUM tracking in web views. Requires:
  - `WebViewTracking.enable(webView:hosts:)` called on the native side
  - Web page instrumented with Datadog Browser SDK
  - See `DatadogWebViewTracking/Sources/WebViewTracking.swift`

## Additional Context

- RUM uses sampling decisions at session start - once a session is sampled out, no events from that session are sent
- Background event tracking (`trackBackgroundEvents`) creates "fake" background views and may increase session count
- View tracking involves method swizzling of UIViewController lifecycle methods
- All automatic tracking can be disabled by not setting predicates; manual tracking always available via `RUMMonitor.shared()`
