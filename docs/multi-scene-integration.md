# Proposed multi-scene integration

This candidate is for code review and real-app integration. The API is proposed and may change. API approval, physical iPhone Duo acceptance, final CI and maintainer approval are still required before merge. It is not an SDK release.

## Install the complete stack

Use the tip of `valpertui/s3-guarded-scene-api-delivery` in `DataDog/dd-sdk-ios`, rather than an intermediate dependency branch. Pin a reviewed commit in your package declaration or Xcode package requirement.

```swift
.package(url: "https://github.com/DataDog/dd-sdk-ios.git",
         branch: "valpertui/s3-guarded-scene-api-delivery")
```

This package requires Swift tools 6.2 or later. Add the existing `DatadogCore` and `DatadogRUM` package products to your application target. Keep the other Datadog products your app uses. Use normal `import DatadogCore` and `import DatadogRUM`; no SPI imports or validation build flags are needed. Package and import migration is allowed for the breaking release. CocoaPods is outside this candidate's release scope.

## Enable tracking

Multi-scene tracking is off by default. Existing instrumentation and enabled SDK features must continue working when it is unused. After any package or import migration, existing apps do not need tracking-call rewrites, new view modifiers, scene registration or manual context propagation.

For an opted-in UIKit app, keep the app's existing UIScene lifecycle and set the flag before enabling RUM:

```swift
import DatadogCore
import DatadogRUM

func configureTelemetry(clientToken: String, applicationID: String) {
    Datadog.initialize(
        with: Datadog.Configuration(clientToken: clientToken, env: "integration"),
        trackingConsent: .granted
    )
    var configuration = RUM.Configuration(
        applicationID: applicationID,
        uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
        uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate()
    )
    configuration.featureFlags[.multiSceneTracking] = true
    RUM.enable(with: configuration)
}
```

Use your application's consent policy rather than copying `.granted` unconditionally. Automatic scene tracking additionally requires iOS 27 or later and Boolean `true` for `UIApplicationSupportsMultipleScenes` inside `UIApplicationSceneManifest`. Earlier systems and unsupported scene configurations use the existing tracking path. Setting the flag does not create application windows or implement the app's scene lifecycle.

## Target manual work

The proposed scene overloads are available on iOS 15 and later. Invoke UI scene APIs on the main thread. Use the scene belonging to the view that owns the work:

```swift
import UIKit
import DatadogRUM

@MainActor
func trackDetail(in scene: UIWindowScene) {
    let monitor = RUMMonitor.shared()
    monitor.startView(key: "detail", name: "Detail", in: scene)
    let target = RUMViewTarget.current(in: scene)
    monitor.addAction(type: .custom, name: "Refresh", view: target)
    monitor.startResource(
        resourceKey: "detail-request",
        url: URL(string: "https://example.invalid/detail")!,
        view: target
    )
    // After completing the request, use the same resource key.
    monitor.stopResource(resourceKey: "detail-request", statusCode: 200, kind: .native)
    monitor.stopView(key: "detail", in: scene)
}
```

`RUMViewTarget.current(in:)` selects the scene's tracked view when the SDK processes the command. It is not a public view ID or a promise to retain a view indefinitely. On earlier systems or when the flag is Off, these overloads keep the existing attribution behavior. Resource and operation ownership follows the SDK's accepted start/completion rules. Navigation callbacks use the currently tracked RUM view; a native completion callback can still belong to Detail before Home becomes the tracked view.

Objective-C uses `DDRUMViewTarget` and the corresponding target-taking monitor selectors. The factory can return `nil` for rejected input. Keep the existing Objective-C error and resource completion methods.

## SwiftUI navigation

The proposed `RUMNavigationHost`, `RUMNavigationDestination` and `RUMNavigationMetadata` APIs require iOS 27 or later. Guard them with `@available` or `if #available` and keep your existing view tracking on older systems. Observe the app's existing router instead of maintaining a second route stack just for telemetry.

```swift
import Combine
import SwiftUI
import DatadogRUM

enum CatalogPage: Hashable { case home, detail }

@available(iOS 27.0, *)
@MainActor
func catalogContent(current: CurrentValueSubject<CatalogPage, Never>) -> some View {
    RUMNavigationHost(
        observing: current,
        destination: { .route($0) },
        metadata: .automatic(in: "catalog")
            .overriding(CatalogPage.detail, name: "Detail", path: "/detail")
    ) {
        Text("Catalog")
    }
}
```

Keep the publisher or router alive for the navigation host's lifetime. A content-only host supports navigation inferred from supported SwiftUI containers. An Observation closure is also proposed under Swift 6.4 or later. Metadata supplies names and paths; it does not change the app's navigation.

## What this candidate establishes

The stack reuses accepted ownership, lifetime, fallback and transition evidence where source and dependencies still apply. Proposed-public changes expose that implementation without changing executable bodies. Normal-import Release Swift 5, Swift 6 and Objective-C consumer compilation, generated-header checks and API baseline diffs are recorded separately from runtime acceptance.

The consumer fixture is a compile/link check, not evidence of backend delivery or a completed real-app journey. Record the pinned revision, integration changes, exercised journeys and observed RUM owners during real-app integration. Those observations supplement the existing evidence.

Split view and tab bar capture limitations remain. The SDK does not promise identical event counts between collapsed and expanded layouts. Attribution must follow the tracked view. Session Replay captured-content correctness, optional networking benchmarks and unavailable React Native SPM integration are outside the completed qualification. Physical Duo and final API approval remain open.
