---
last_updated: 2025-01-03
sdk_version: 3.3.0
verified_against_commit: 1d3e80ec5
---

# RUM (Real User Monitoring) Feature

## Overview

RUM tracks user interactions, views, resources, errors, and performance metrics in iOS applications. It requires initialization via `Datadog.initialize()` before enabling.

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
        swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
        
        // SwiftUI automatic action tracking - provide predicate to enable
        // Default: nil (disabled)
        // Or use custom: MyCustomActionsPredicate()
        // Note: Also requires uiKitActionsPredicate for SwiftUI tracking to work correctly
        swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
        
        // Automatic network resource tracking - provide config to enable
        // Default: nil (disabled)
        urlSessionTracking: RUM.Configuration.URLSessionTracking(
            // Optional: Enable distributed tracing for first-party hosts
            firstPartyHostsTracing: .trace(
                hosts: ["api.example.com", "example.com"],
                sampleRate: 100.0
            ),
            // Optional: Add custom attributes to resources
            resourceAttributesProvider: { request, response, data, error in
                return ["custom.attribute": "value"]
            }
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
        onSessionStart: { sessionId, isDiscarded in
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
        
        // SDK telemetry sampling rate (for Datadog internal monitoring)
        // Default: 20.0
        telemetrySampleRate: 20.0,
        
        // Collect accessibility settings in view events
        // Default: false
        collectAccessibility: false
    )
)

// 3. Enable network instrumentation
// This must be called AFTER RUM.enable()
URLSessionInstrumentation.trackMetrics(
    with: .init(delegateClass: CustomURLSessionDelegate.self)
)

// 4. Use RUM Monitor for manual tracking
let monitor = RUMMonitor.shared()

// Start a view
monitor.startView(key: "ProductList", name: "Product List Screen")

// Add custom error
monitor.addError(message: "Failed to load products", source: .network)

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
  - Errors: `addError()`
  - Resources: `startResource()`, `stopResource()`
  - Actions: `addAction()`, `startAction()`, `stopAction()`
  - Custom attributes, timings, and feature flags

### Implementation
- **`DatadogRUM/Sources/Feature/RUMFeature.swift`** - Internal feature implementation. Shows how configuration translates to behavior.

## Configuration Categories

### Automatic Tracking
Requires configuration to be set, otherwise disabled by default:
- **View tracking**: `uiKitViewsPredicate`, `swiftUIViewsPredicate`
- **Action tracking**: `uiKitActionsPredicate`, `swiftUIActionsPredicate`
- **Resource tracking**: `urlSessionTracking` and call `URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: YourSessionDelegate.self))`

### Performance Monitoring
- **Long tasks**: `longTaskThreshold` (default: 0.1s)
- **App hangs**: `appHangThreshold` (default: nil/disabled)
- **Vitals**: `vitalsUpdateFrequency` (default: .average)

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

## Common Troubleshooting Patterns

### "No RUM data appearing"
1. Check `Datadog.initialize()` and `RUM.enable()` were called
2. Verify session wasn't sampled out (check `sessionSampleRate`)

### "Views or actions not tracked"
1. Check if predicates are configured in RUMConfiguration
2. For UIKit: `uiKitViewsPredicate` and `uiKitActionsPredicate` must be set
3. For SwiftUI: `swiftUIViewsPredicate` and `swiftUIActionssPredicate` must be set, as well as UIKit predicates

### "Network requests not tracked"
1. Verify `urlSessionTracking` is configured in RUMConfiguration (RUM.enable() handles URLSessionInstrumentation internally)
2. Ensure `URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: YourSessionDelegate.self))` is called after RUM has been enabled
3. Ensure network requests use instrumented URLSession

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