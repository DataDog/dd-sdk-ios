---
last_updated: 2025-01-03
sdk_version: 3.3.0
verified_against_commit: 1d3e80ec5
---

# Session Replay Feature

## Overview

Session Replay records and replays user sessions as video-like reproductions. It captures the visual state of the app, user interactions, and navigation. Session Replay requires RUM to be enabled first.

**Platform**: iOS only (not available on tvOS, macOS, watchOS)

## Quick Start Example

```swift
import DatadogCore
import DatadogRUM
import DatadogSessionReplay

// 1. Initialize Core SDK first
Datadog.initialize(
    with: Datadog.Configuration(
        clientToken: "<client_token>",
        env: "<environment>"
    ),
    trackingConsent: .granted
)

// 2. Enable RUM first (required for Session Replay)
// Session Replay requires view and action tracking to be enabled
RUM.enable(
    with: RUM.Configuration(
        applicationID: "<rum_application_id>",
        // For pure UIKit apps: UIKit predicates are enough
        uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
        uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate(),
        // For SwiftUI or mixed apps: Both UIKit AND SwiftUI predicates needed
        swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
        swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate()
    )
)

// 3. Enable Session Replay
SessionReplay.enable(
    with: SessionReplay.Configuration(
        // Sampling rate for Session Replay (applied ON TOP of RUM session sampling)
        // Example: 80% RUM × 20% SR = 16% of total sessions have replay
        // Default: 100.0
        replaySampleRate: 100.0,
        
        // Text and input masking level
        // Default: .maskAll
        // Options:
        //   .maskSensitiveInputs - Show all texts except sensitive inputs (passwords)
        //   .maskAllInputs - Mask all input fields (textfields, switches, checkboxes)
        //   .maskAll - Mask all texts and inputs (labels, etc.)
        textAndInputPrivacyLevel: .maskAll,
        
        // Image masking level
        // Default: .maskAll
        // Options:
        //   .maskNonBundledOnly - Only show bundled images (SF Symbols, UIImage(named:))
        //   .maskAll - No images recorded
        //   .maskNone - All images recorded (including downloaded/generated)
        imagePrivacyLevel: .maskAll,
        
        // Touch interaction masking
        // Default: .hide
        // Options:
        //   .show - Show all user touches
        //   .hide - Hide all user touches
        touchPrivacyLevel: .hide,
        
        // Start recording automatically when enabled
        // Default: true
        // If false, call SessionReplay.startRecording() manually
        startRecordingImmediately: true,
        
        // Custom endpoint for replay data
        // Default: nil (uses Datadog intake)
        customEndpoint: nil,
        
        // Feature flags for experimental features
        // Default: [.swiftui: false]
        featureFlags: [
            .swiftui: true  // Enable SwiftUI recording (experimental)
        ]
    )
)

// 4. (Optional) Manual recording control
// Use cases:
// - Start recording later if startRecordingImmediately: false
// - Stop/resume recording dynamically based on app state
SessionReplay.startRecording()
SessionReplay.stopRecording()

// 5. (Optional) Per-view privacy overrides (UIKit)
// Override privacy settings for specific UIKit views
myPasswordField.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskAll
mySensitiveImage.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskAll
myInteractiveView.dd.sessionReplayPrivacyOverrides.touchPrivacy = .hide
myView.dd.sessionReplayPrivacyOverrides.hide = true  // Render as opaque wireframe

// 6. (Optional) Per-view privacy overrides (SwiftUI)
// Use SessionReplayPrivacyView to wrap SwiftUI content (iOS 16+)
SessionReplayPrivacyView(
    textAndInputPrivacy: .maskAll,
    imagePrivacy: .maskAll,
    touchPrivacy: .hide,
    hide: false
) {
    // Your SwiftUI content here
    Text(user.name)
    AsyncImage(url: user.avatarURL)
}
```

## Key Files

### Feature Entry Point
- **`DatadogSessionReplay/Sources/SessionReplay.swift`** - Main entry point. Call `SessionReplay.enable(with:)` to activate.
  - `startRecording()` - Start recording manually
  - `stopRecording()` - Stop recording manually

### Configuration
- **`DatadogSessionReplay/Sources/SessionReplayConfiguration.swift`** - All configuration options
  - Sampling rate, privacy levels, feature flags

### Privacy Overrides (Per-View)
- **`DatadogSessionReplay/Sources/SessionReplayPrivacyOverrides.swift`** - UIKit per-view privacy control
  - Access via `view.dd.sessionReplayPrivacyOverrides`
  - Override text, image, touch privacy per view
  - Hide specific views entirely
- **`DatadogSessionReplay/Sources/SessionReplayPrivacyView.swift`** - SwiftUI per-view privacy control (iOS 16+)
  - Use `SessionReplayPrivacyView { ... }` wrapper
  - Same privacy options as UIKit overrides

### Privacy Level Enums
- **`DatadogInternal/Sources/Models/SessionReplay/SessionReplayConfiguration.swift`** - Privacy level definitions
  - `TextAndInputPrivacyLevel`: `.maskSensitiveInputs`, `.maskAllInputs`, `.maskAll`
  - `ImagePrivacyLevel`: `.maskNonBundledOnly`, `.maskAll`, `.maskNone`
  - `TouchPrivacyLevel`: `.show`, `.hide`

### Implementation
- **`DatadogSessionReplay/Sources/Feature/SessionReplayFeature.swift`** - Internal feature implementation

## Configuration Categories

### Sampling
- **Session Replay sampling**: `replaySampleRate` (default: 100%)
  - Applied ON TOP of RUM session sampling
  - If RUM samples 80% and SR samples 20%, only 16% of total sessions have replay

### Privacy Levels
Global privacy settings applied to all views:
- **Text/Input**: `textAndInputPrivacyLevel` (default: `.maskAll`)
- **Images**: `imagePrivacyLevel` (default: `.maskAll`)
- **Touches**: `touchPrivacyLevel` (default: `.hide`)

### Recording Control
- **Auto-start**: `startRecordingImmediately` (default: `true`)
- **Manual control**: `SessionReplay.startRecording()` / `SessionReplay.stopRecording()`

### Per-View Privacy Overrides
Override global privacy for specific views:

**UIKit:**
```swift
view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskNone
view.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskNone
view.dd.sessionReplayPrivacyOverrides.touchPrivacy = .show
view.dd.sessionReplayPrivacyOverrides.hide = true  // Completely hide view and subviews
```

**SwiftUI (iOS 16+):**
```swift
SessionReplayPrivacyView(
    textAndInputPrivacy: .maskNone,
    imagePrivacy: .maskNone,
    touchPrivacy: .show,
    hide: false
) {
    // Content to apply overrides to
}
```

## Common Troubleshooting Patterns

### "No Session Replay data"
1. Verify RUM is enabled first - Session Replay requires RUM
2. Check RUM view and action predicates are configured (required for Session Replay)
3. Check RUM and Session Replay sample rates are > 0
4. Remember: SR sampling is applied ON TOP of RUM sampling

### "Recording not starting"
1. Check `startRecordingImmediately` is `true`, OR
2. Call `SessionReplay.startRecording()` manually if set to `false`

### "Sensitive data visible in replay"
1. Increase privacy levels in configuration
2. Use per-view overrides for specific views: `view.dd.sessionReplayPrivacyOverrides`
3. Set `hide = true` to completely hide sensitive views, this will also hide subviews

### "Images not showing in replay"
1. Check `imagePrivacyLevel` setting
2. `.maskAll` = no images shown
3. `.maskNonBundledOnly` = only bundled images shown
4. `.maskNone` = all images shown (use with caution)

**Note on `.maskNonBundledOnly` behavior:**
- **UIKit**: Detects bundled images via `UIImage(named:)` and SF Symbols
- **SwiftUI**: Cannot detect bundled images directly, uses heuristic: images ≤ 100 points (width and height) are considered bundled

### "SwiftUI views not recorded"
1. Enable SwiftUI feature flag: `featureFlags: [.swiftui: true]`
2. Note: Session Replay SwiftUI is experimental, and some components are not supported

## Feature Interactions

- **RUM**: Required - Session Replay cannot work without RUM enabled. View and action tracking must be configured.
- **WebView Tracking**: Enables Session Replay in web views. Requires:
  - `WebViewTracking.enable(webView:hosts:)` called on the native side
  - Web page instrumented with Datadog Browser SDK
  - See `DatadogWebViewTracking/Sources/WebViewTracking.swift`
- **Tracking Consent**: Respects user consent settings from Core SDK

## Additional Context

- Session Replay is iOS only (not available on tvOS, macOS, watchOS)
- Recording captures visual state, not actual screen pixels
- Per-view overrides inherit from parent views if not explicitly set
- `hide = true` renders view as opaque wireframe in replay and hide subviews as well
- Multiple Session Replay instances are not supported - only one can be enabled
