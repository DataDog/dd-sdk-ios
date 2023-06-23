/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Bundles RUM instrumentation components.
internal final class RUMInstrumentation: RUMCommandPublisher {
    /// Swizzles `UIViewController` for intercepting its lifecycle callbacks.
    /// It is `nil` (no swizzling) if RUM View instrumentaiton is not enabled.
    let viewControllerSwizzler: UIViewControllerSwizzler?
    /// Receives interceptions from `UIViewControllerSwizzler` and from SwiftUI instrumentation.
    /// It is non-optional as we can't know if SwiftUI instrumentation will be used or not.
    let viewsHandler: RUMViewsHandler

    /// Swizzles `UIApplication` for intercepting `UIEvents` passed to the app.
    /// It is `nil` (no swizzling) if RUM Action instrumentaiton is not enabled.
    let uiApplicationSwizzler: UIApplicationSwizzler?
    /// Receives interceptions from `UIApplicationSwizzler`.
    /// It is `nil` if RUM Action instrumentaiton is not enabled.
    let actionsHandler: UIEventHandler?

    /// Instruments RUM Long Tasks. It is `nil` if long tasks tracking is not enabled.
    let longTasks: LongTaskObserver?

    // MARK: - Initialization

    init(
        uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?,
        uiKitRUMActionsPredicate: UIKitRUMUserActionsPredicate?,
        longTaskThreshold: TimeInterval?,
        dateProvider: DateProvider
    ) {
        // Always create views handler (we can't know if it will be used by SwiftUI instrumentation)
        // and only swizzle `UIViewController` if UIKit instrumentation is configured:
        let viewsHandler = RUMViewsHandler(dateProvider: dateProvider, predicate: uiKitRUMViewsPredicate)
        var viewControllerSwizzler: UIViewControllerSwizzler? = nil

        // Create actions handler and `UIApplicationSwizzler` only if UIKit instrumentation is configured:
        var actionsHandler: UIKitRUMUserActionsHandler? = nil
        var uiApplicationSwizzler: UIApplicationSwizzler? = nil

        // Create long tasks observer only if configured:
        var longTasks: LongTaskObserver? = nil

        do {
            if uiKitRUMViewsPredicate != nil {
                // UIKit views instrumentation is enabled, so install the swizzler:
                viewControllerSwizzler = try UIViewControllerSwizzler(handler: viewsHandler)
            }
        } catch {
            consolePrint(
                "🔥 Datadog SDK error: UIKit RUM Views tracking can't be enabled due to error: \(error)"
            )
        }

        do {
            if let predicate = uiKitRUMActionsPredicate {
                let handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, predicate: predicate)
                actionsHandler = handler
                uiApplicationSwizzler = try UIApplicationSwizzler(handler: handler)
            }
        } catch {
            consolePrint(
                "🔥 Datadog SDK error: RUM Actions tracking can't be enabled due to error: \(error)"
            )
        }

        if let threshold = longTaskThreshold, threshold > 0 {
            longTasks = LongTaskObserver(threshold: threshold, dateProvider: dateProvider)
        }

        self.viewsHandler = viewsHandler
        self.viewControllerSwizzler = viewControllerSwizzler
        self.actionsHandler = actionsHandler
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.longTasks = longTasks

        // Enable configured instrumentations:
        self.viewControllerSwizzler?.swizzle()
        self.uiApplicationSwizzler?.swizzle()
        self.longTasks?.start()
    }

    deinit {
        // Disable configured instrumentations:
        viewControllerSwizzler?.unswizzle()
        uiApplicationSwizzler?.unswizzle()
        longTasks?.stop()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        viewsHandler.publish(to: subscriber)
        actionsHandler?.publish(to: subscriber)
        longTasks?.publish(to: subscriber)
    }
}
