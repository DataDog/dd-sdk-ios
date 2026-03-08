# DatadogRUM – Modern Concurrency Migration

This document tracks the decisions, patterns, and learnings from migrating DatadogRUM to Swift 6 strict concurrency.

## Overview

The DatadogRUM module was compiled with `swiftLanguageMode(.v6)` while `DatadogInternal` remains in Swift 5 mode. This means the full `Sendable` and actor isolation enforcement applies within RUM, but types crossing from `DatadogInternal` may need explicit `Sendable` annotations.

## Key Patterns Applied

### 1. `@MainActor` for UIKit Event Processing Chain

UIKit event delivery (swizzled `sendEvent`, `viewDidAppear`, `viewDidDisappear`) runs on the main thread. In Swift 6, UIKit types like `UIView`, `UITouch`, and `UIViewController` are `@MainActor`-isolated.

**Strategy**: Mark methods that access UIKit properties as `@MainActor`, flowing from protocols down to implementations:

- `UIEventCommandFactory.command(from:)` – protocol method marked `@MainActor`
- `UIViewControllerHandler.notify_viewDidAppear/Disappear` – protocol methods marked `@MainActor`
- `RUMActionsHandling.notify_sendEvent` – protocol method marked `@MainActor`
- Private helpers (`createUIKitActionCommand`, `bestActionTarget`, `handleTouchBegan`, `createCommandFromPendingTouch`) – marked `@MainActor` since they access UIKit properties
- `SwiftUIComponentHelpers.extractComponentName` – marked `@MainActor`
- `UITouchRUMActionsPredicate` / `UIPressRUMActionsPredicate` – **public** protocols marked `@MainActor & Sendable` (methods take `UIView`)
- `SwiftUIRUMActionsPredicate` – **public** protocol marked `Sendable`
- `SwiftUIComponentDetector` – **internal** protocol marked `@MainActor & Sendable`
- `UIEventCommandFactory` – **internal** protocol marked `@MainActor`
- `DefaultUIKitRUMActionsPredicate.targetName(for:)` – `@MainActor` (no longer needs `MainActor.assumeIsolated`)

**Key principle**: Apply `@MainActor` at the **method** level when conforming types have mixed isolation needs. When a protocol and all its conforming types exclusively interact with UIKit, apply `@MainActor` at the **protocol/class** level instead.

#### Full `@MainActor` Isolation for SwiftUI Component Detection

The `SwiftUIComponentDetector` protocol and its implementations (`ModernSwiftUIComponentDetector`, `LegacySwiftUIComponentDetector`) are marked `@MainActor` at the type level because they exclusively handle UIKit touches and gesture recognizers:

- `SwiftUIComponentDetector` – protocol marked `@MainActor` (sole method `createActionCommand` accesses `UITouch`)
- `ModernSwiftUIComponentDetector` – class marked `@MainActor`, `nonisolated init()` allows creation from any context
- `LegacySwiftUIComponentDetector` – class marked `@MainActor`, `nonisolated init()` allows creation from any context
- `SwiftUIComponentHelpers` – class marked `@MainActor` (sole method accesses gesture recognizers)
- `RUMDebugging` – class marked `@MainActor`, `nonisolated init()` and `nonisolated func debug()` allow entry from non-main-actor contexts

### 2. `MainActor.assumeIsolated` for Bridging Swizzled Code

Swizzled methods execute on the main thread via UIKit's event delivery, but the compiler can't statically verify this. We use `MainActor.assumeIsolated` to bridge these contexts:

- **`UIApplicationSwizzler.SendEvent.swizzle()`** – wraps `handler?.notify_sendEvent` call
- **`UIViewControllerSwizzler.ViewDidAppear/ViewDidDisappear.swizzle()`** – wraps handler calls
- **`FrameInfoProvider` CADisplayLink extension** – wraps `UIScreen.main.maximumFramesPerSecond` access
- **`VitalInfoSampler.maximumFramesPerSecond`** – guards with `Thread.isMainThread` before wrapping `UIScreen.main` access (falls back to 60.0 when off main thread, since this property is used as a default parameter that can be evaluated from any thread)
- **`RUMDebugging.debug()`** – wraps `renderOnMainThread` call inside `DispatchQueue.main.async`

### 3. `nonisolated` for Thread-Safe UIViewController Properties

Some `UIViewController` extension properties only use `NSStringFromClass` or type checks, which are inherently thread-safe. These are marked `nonisolated` to prevent `@MainActor` inheritance from `UIViewController`:

- `UIViewController.canonicalClassName` – uses `NSStringFromClass(type(of: self))`
- `UIViewController.isUIAlertController` – uses `self is UIAlertController`

### 4. `nonisolated(unsafe)` for Swizzler Handler Captures

Swizzlers need to capture their handler weakly in `@Sendable` closures. Since the handlers aren't `Sendable` but are only accessed within `MainActor.assumeIsolated`, we use `nonisolated(unsafe)` local variables:

```swift
func swizzle() {
    nonisolated(unsafe) weak var handler = self.handler
    swizzle(method) { previousImplementation -> Signature in
        return { application, event in
            MainActor.assumeIsolated {
                handler?.notify_sendEvent(application: application, event: event)
            }
            return previousImplementation(application, Self.selector, event)
        }
    }
}
```

### 5. `@unchecked Sendable` for Types with Internal Synchronization

Types that manage their own thread safety via `DispatchQueue`, `ReadWriteLock`, or are designed for main-thread-only use:

| Type | Synchronization Mechanism |
|------|--------------------------|
| `ValuePublisher<Value>` | Concurrent `DispatchQueue` with barrier writes |
| `ViewHitchesReader` | Serial `DispatchQueue` |
| `VitalRefreshRateReader` | Main-thread only (CADisplayLink callbacks) |
| `RUMDebugging` | `DispatchQueue.main` for all UIKit access |
| `AccessibilityReader` | `@ReadWriteLock` property wrapper |
| `objc_HeaderCaptureRule` | Immutable (`let` properties only) |
| `objc_TrackResourceHeaders` | Immutable (`let` properties only) |

### 6. `Encodable & Sendable` for Cross-Isolation Attributes

`AttributeValue` is already `Encodable & Sendable` in `DatadogInternal`. Updated types that used plain `Encodable` to match:

- `RUMErrorMessage.attributes: [String: Encodable & Sendable]` (in `DatadogInternal`)
- `RUMFlagEvaluationMessage.value: any Encodable & Sendable` (in `DatadogInternal`)
- `FatalErrorContextNotifier.globalAttributes: [String: Encodable & Sendable]`
- `RUMActionsHandling.notify_viewModifierTapped(actionAttributes:)` parameter
- `RUMTapActionModifier.attributes` and the public `trackRUMTapAction(attributes:)` API

### 7. Static Property Safety

- `VitalRefreshRateReader.backendSupportedFrameRate` – changed from `static var` to `static let` (value never changes)
- `RUMViewOutline.Constants.viewNameTextAttributes/viewDetailsTextAttributes` – marked `nonisolated(unsafe)` (immutable dictionaries with UIKit values that don't nominally conform to `Sendable`)

### 8. Explicit `self.` in Closures

Swift 6 requires explicit `self.` for property access in closures (stricter than Swift 5):

- `RUMAppLaunchManager` – added `self.` for `timeToFullDisplay`, `dependencies.rumUUIDGenerator`, `telemetryController`

### 9. `ObjectIdentifier` for Sendable Identity Comparison

`ValuePublisher.unsubscribe` needed to compare observer identity (`===`) inside a `@Sendable` closure. Instead of capturing the non-Sendable observer, we extract `ObjectIdentifier` (which is `Sendable`) before the closure:

```swift
func unsubscribe<Observer: ValueObserver>(_ observer: Observer) {
    let observerIdentity = ObjectIdentifier(observer)
    concurrentQueue.async(flags: .barrier) {
        self.unsafeObservers.removeAll { existingObserver in
            ObjectIdentifier(existingObserver.object) == observerIdentity
        }
    }
}
```

## Public API Changes

The following public API changes were necessary for Swift 6 compatibility:

1. **`trackRUMTapAction(name:attributes:count:in:)`** – `attributes` parameter changed from `[String: Encodable]` to `[String: Encodable & Sendable]`

This aligns with the existing `AttributeValue` typealias (`Encodable & Sendable`) and is a source-compatible change for the vast majority of user code since common Swift types (`String`, `Int`, `Double`, `Bool`, `Array`, `Dictionary`) already conform to `Sendable`.

2. **`UITouchRUMActionsPredicate`** and **`UIPressRUMActionsPredicate`** – protocols marked `@MainActor & Sendable`

These protocols' methods take `UIView` parameters, which are `@MainActor`-isolated in Swift 6. Users implementing these predicates in Swift 6 mode would already need main-actor isolation to access `UIView` properties. The `Sendable` conformance enables storing them as properties in `@MainActor` types with `nonisolated init` without `nonisolated(unsafe)`. The corresponding ObjC protocols (`objc_UITouchRUMActionsPredicate`, `objc_UIPressRUMActionsPredicate`) were also marked `@MainActor`.

3. **`SwiftUIRUMActionsPredicate`** – protocol marked `Sendable`

This protocol's method takes `String` (no UIKit types), so `@MainActor` is not needed. `Sendable` enables safe storage across isolation boundaries.

## Future Work

The following areas are candidates for deeper concurrency migration in subsequent phases:

- **DispatchQueue to Actor migration** – `ValuePublisher` and `ViewHitchesReader` could potentially be converted to actors
- **ReadWriteLock evaluation** – Consider whether `@ReadWriteLock` usages should remain or convert to actor-based isolation
- **Callback to async/await conversion** – Some internal APIs still use callback patterns that could benefit from `async/await`
- **Additional Sendable conformances** – `RUMEventsMapper`, `RUMEventBuilder`, and other key types may benefit from explicit `Sendable` conformance

## Files Modified

### DatadogInternal
- `Sources/Models/RUM/RUMPayloadMessages.swift` – `RUMErrorMessage.attributes`, `RUMFlagEvaluationMessage.value` → `Sendable`

### DatadogRUM
- `Sources/Integrations/FatalErrorContextNotifier.swift` – `globalAttributes` → `Sendable`
- `Sources/Instrumentation/Actions/RUMActionsHandler.swift` – `@MainActor` on `notify_sendEvent`, `Sendable` on `notify_viewModifierTapped`
- `Sources/Instrumentation/Actions/UIKit/UIApplicationSwizzler.swift` – `nonisolated(unsafe)` handler, `MainActor.assumeIsolated`
- `Sources/Instrumentation/Actions/UIKit/UIEventCommandFactory.swift` – `@MainActor` on protocol, `UITouchCommandFactory`, `UIPressCommandFactory`; `nonisolated(unsafe) let` for non-Sendable stored properties
- `Sources/Instrumentation/Actions/UIKit/UIKitRUMUserActionsPredicate.swift` – `@MainActor` on `UITouchRUMActionsPredicate`, `UIPressRUMActionsPredicate` protocols; removed `MainActor.assumeIsolated` from `targetName`
- `Sources/Instrumentation/Actions/SwiftUI/SwiftUIActionModifier.swift` – `Sendable` attributes
- `Sources/Instrumentation/Actions/SwiftUI/SwiftUIComponentDetector.swift` – `@MainActor` on protocol, `SwiftUIComponentHelpers`
- `Sources/Instrumentation/Actions/SwiftUI/ModernSwiftUIComponentDetector.swift` – `@MainActor` class, `nonisolated init()`
- `Sources/Instrumentation/Actions/SwiftUI/LegacySwiftUIComponentDetector.swift` – `@MainActor` class, `nonisolated init()`
- `Sources/Instrumentation/Views/UIKit/UIViewControllerHandler.swift` – `@MainActor` on protocol methods
- `Sources/Instrumentation/Views/UIKit/UIViewControllerSwizzler.swift` – `nonisolated(unsafe)` handler
- `Sources/Instrumentation/Views/UIKit/UIKitRUMViewsPredicate.swift` – (benefits from `nonisolated` UIKitExtensions)
- `Sources/RUMMonitor/Scopes/RUMAppLaunchManager.swift` – explicit `self.` in closures
- `Sources/RUMMonitor/Monitor.swift` – (benefits from `nonisolated` `canonicalClassName`)
- `Sources/RUMContext/AccessibilityReader.swift` – `@unchecked Sendable`
- `Sources/RUMVitals/RenderLoop/VitalRefreshRateReader.swift` – `@unchecked Sendable`, `static let`
- `Sources/RUMVitals/RenderLoop/ViewHitchesReader.swift` – `@unchecked Sendable`
- `Sources/RUMVitals/RenderLoop/Providers/FrameInfoProvider.swift` – `MainActor.assumeIsolated`
- `Sources/RUMVitals/VitalInfoSampler.swift` – `MainActor.assumeIsolated`
- `Sources/Utils/ValuePublisher.swift` – `@unchecked Sendable`, `ObjectIdentifier` pattern
- `Sources/Utils/UIKitExtensions.swift` – `nonisolated` on `canonicalClassName`, `isUIAlertController`
- `Sources/Debugging/RUMDebugging.swift` – `@unchecked Sendable`, `@MainActor`, `nonisolated(unsafe)`
- `Sources/RUM+objc.swift` – `@unchecked Sendable` on ObjC bridge types
