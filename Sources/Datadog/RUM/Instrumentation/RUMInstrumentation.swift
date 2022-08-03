/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// RUM Auto Instrumentation feature.
internal final class RUMInstrumentation: RUMCommandPublisher {
    /// RUM User Actions auto instrumentation.
    class UserActionsAutoInstrumentation {
        let swizzler: UIApplicationSwizzler
        let handler: UIEventHandler

        init(dateProvider: DateProvider, predicate: UIKitRUMUserActionsPredicate) throws {
            handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, predicate: predicate)
            swizzler = try UIApplicationSwizzler(handler: handler)
        }

        func enable() {
            swizzler.swizzle()
        }
    }

    let viewsHandler: RUMViewsHandler
    /// RUM Views auto instrumentation, `nil` if not enabled.
    let viewControllerSwizzler: UIViewControllerSwizzler?
    /// RUM User Actions auto instrumentation, `nil` if not enabled.
    let userActionsAutoInstrumentation: UserActionsAutoInstrumentation?
    /// RUM Long Tasks auto instrumentation, `nil` if not enabled.
    let longTasks: LongTaskObserver?

    // MARK: - Initialization

    init(
        configuration: FeaturesConfiguration.RUM.Instrumentation,
        dateProvider: DateProvider
    ) {
        viewsHandler = RUMViewsHandler(
           dateProvider: dateProvider,
           predicate: configuration.uiKitRUMViewsPredicate
        )

        var viewsAutoInstrumentation: UIViewControllerSwizzler?
        var userActionsAutoInstrumentation: UserActionsAutoInstrumentation?
        var longTasks: LongTaskObserver?

        do {
            if configuration.uiKitRUMViewsPredicate != nil {
                // UIKit auto instrumentation is enabled, so we need to install swizzler
                viewsAutoInstrumentation = try UIViewControllerSwizzler(handler: viewsHandler)
            }

            if let predicate = configuration.uiKitRUMUserActionsPredicate {
                userActionsAutoInstrumentation = try UserActionsAutoInstrumentation(dateProvider: dateProvider, predicate: predicate)
            }
        } catch {
            consolePrint(
                "🔥 Datadog SDK error: RUM automatic tracking can't be set up due to error: \(error)"
            )
        }

        if let threshold = configuration.longTaskThreshold {
            longTasks = LongTaskObserver(threshold: threshold, dateProvider: dateProvider)
        }

        self.viewControllerSwizzler = viewsAutoInstrumentation
        self.userActionsAutoInstrumentation = userActionsAutoInstrumentation
        self.longTasks = longTasks
    }

    func enable() {
        viewControllerSwizzler?.swizzle()
        userActionsAutoInstrumentation?.enable()
        longTasks?.start()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        viewsHandler.publish(to: subscriber)
        userActionsAutoInstrumentation?.handler.publish(to: subscriber)
        longTasks?.publish(to: subscriber)
    }

    /// Removes RUM instrumentation swizzlings and deinitializes this component.
    internal func deinitialize() {
        viewControllerSwizzler?.unswizzle()
        userActionsAutoInstrumentation?.swizzler.unswizzle()
    }
}
