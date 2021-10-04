/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// RUM Auto Instrumentation feature.
internal final class RUMAutoInstrumentation {
    static var instance: RUMAutoInstrumentation?

    /// RUM Views auto instrumentation.
    class Views {
        let swizzler: UIViewControllerSwizzler
        let handler: UIKitRUMViewsHandlerType

        init(
            uiKitRUMViewsPredicate: UIKitRUMViewsPredicate,
            dateProvider: DateProvider
        ) throws {
            handler = UIKitRUMViewsHandler(
                predicate: uiKitRUMViewsPredicate,
                dateProvider: dateProvider
            )
            swizzler = try UIViewControllerSwizzler(handler: handler)
        }

        func enable() {
            swizzler.swizzle()
        }
    }

    /// RUM User Actions auto instrumentation.
    class UserActions {
        let swizzler: UIApplicationSwizzler
        let handler: UIKitRUMUserActionsHandlerType

        init(dateProvider: DateProvider, rumUserActionsPredicate: UIKitRUMUserActionsPredicate) throws {
            handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, userActionsPredicate: rumUserActionsPredicate)
            swizzler = try UIApplicationSwizzler(handler: handler)
        }

        func enable() {
            swizzler.swizzle()
        }
    }

    /// RUM Views auto instrumentation, `nil` if not enabled.
    let views: Views?
    /// RUM User Actions auto instrumentation, `nil` if not enabled.
    let userActions: UserActions?
    /// RUM Long Tasks auto instrumentation, `nil` if not enabled.
    let longTasks: LongTaskObserver?

    // MARK: - Initialization

    init?(
        configuration: FeaturesConfiguration.RUM.AutoInstrumentation,
        dateProvider: DateProvider
    ) {
        do {
            if let uiKitRUMViewsPredicate = configuration.uiKitRUMViewsPredicate {
                views = try Views(uiKitRUMViewsPredicate: uiKitRUMViewsPredicate, dateProvider: dateProvider)
            } else {
                views = nil
            }
            if let uiKitUserActionsPredicate = configuration.uiKitRUMUserActionsPredicate {
                userActions = try UserActions(dateProvider: dateProvider, rumUserActionsPredicate: uiKitUserActionsPredicate)
            } else {
                userActions = nil
            }

            if let threshold = configuration.longTaskThreshold {
                longTasks = LongTaskObserver(threshold: threshold, dateProvider: dateProvider)
            } else {
                longTasks = nil
            }
        } catch {
            consolePrint(
                "🔥 Datadog SDK error: RUM automatic tracking can't be set up due to error: \(error)"
            )
            return nil
        }
    }

    func enable() {
        views?.enable()
        userActions?.enable()
        longTasks?.start()
    }

    func subscribe(commandSubscriber: RUMCommandSubscriber) {
        views?.handler.subscribe(commandsSubscriber: commandSubscriber)
        userActions?.handler.subscribe(commandsSubscriber: commandSubscriber)
        longTasks?.subscribe(commandsSubscriber: commandSubscriber)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    /// Removes RUM instrumentation swizzlings and deinitializes this component.
    func deinitialize() {
        views?.swizzler.unswizzle()
        userActions?.swizzler.unswizzle()
        RUMAutoInstrumentation.instance = nil
    }
#endif
}
