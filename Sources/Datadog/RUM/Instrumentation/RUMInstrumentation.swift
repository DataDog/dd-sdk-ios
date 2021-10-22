/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// RUM Auto Instrumentation feature.
internal final class RUMInstrumentation: RUMCommandPublisher {
    static var instance: RUMInstrumentation?

    /// RUM Views auto instrumentation.
    class ViewsAutoInstrumentation {
        let swizzler: UIViewControllerSwizzler
        let handler: UIViewControllerHandler

        init(
            predicate: UIKitRUMViewsPredicate,
            dateProvider: DateProvider
        ) throws {
            handler = UIKitRUMViewsHandler(
                predicate: predicate,
                dateProvider: dateProvider
            )
            swizzler = try UIViewControllerSwizzler(handler: handler)
        }

        func enable() {
            swizzler.swizzle()
        }
    }

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

    /// RUM Views auto instrumentation, `nil` if not enabled.
    let viewsAutoInstrumentation: ViewsAutoInstrumentation?
    /// `SwiftUI.View` RUM instrumentation
    let swiftUIViewInstrumentation: SwiftUIViewHandler
    /// RUM User Actions auto instrumentation, `nil` if not enabled.
    let userActionsAutoInstrumentation: UserActionsAutoInstrumentation?
    /// RUM Long Tasks auto instrumentation, `nil` if not enabled.
    let longTasks: LongTaskObserver?

    // MARK: - Initialization

    init(
        configuration: FeaturesConfiguration.RUM.Instrumentation,
        dateProvider: DateProvider
    ) {
        var viewsAutoInstrumentation: ViewsAutoInstrumentation?
        var userActionsAutoInstrumentation: UserActionsAutoInstrumentation?
        var longTasks: LongTaskObserver?

        do {
            if let predicate = configuration.uiKitRUMViewsPredicate {
                viewsAutoInstrumentation = try ViewsAutoInstrumentation(predicate: predicate, dateProvider: dateProvider)
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

        self.viewsAutoInstrumentation = viewsAutoInstrumentation
        self.userActionsAutoInstrumentation = userActionsAutoInstrumentation
        self.longTasks = longTasks
        self.swiftUIViewInstrumentation = SwiftUIRUMViewsHandler(dateProvider: dateProvider)
    }

    func enable() {
        viewsAutoInstrumentation?.enable()
        userActionsAutoInstrumentation?.enable()
        longTasks?.start()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        viewsAutoInstrumentation?.handler.publish(to: subscriber)
        userActionsAutoInstrumentation?.handler.publish(to: subscriber)
        longTasks?.publish(to: subscriber)
        swiftUIViewInstrumentation.publish(to: subscriber)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    /// Removes RUM instrumentation swizzlings and deinitializes this component.
    func deinitialize() {
        viewsAutoInstrumentation?.swizzler.unswizzle()
        userActionsAutoInstrumentation?.swizzler.unswizzle()
        RUMInstrumentation.instance = nil
    }
#endif
}

extension RUMInstrumentation: SwiftUIViewHandler {
    func onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue]) {
        swiftUIViewInstrumentation.onAppear(identity: identity, name: name, path: path, attributes: attributes)
    }

    func onDisappear(identity: String) {
        swiftUIViewInstrumentation.onDisappear(identity: identity)
    }
}
