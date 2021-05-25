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

        init(dateProvider: DateProvider) throws {
            handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider)
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
            if configuration.uiKitActionsTrackingEnabled {
                userActions = try UserActions(dateProvider: dateProvider)
            } else {
                userActions = nil
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
    }

    func subscribe(commandSubscriber: RUMCommandSubscriber) {
        views?.handler.subscribe(commandsSubscriber: commandSubscriber)
        userActions?.handler.subscribe(commandsSubscriber: commandSubscriber)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        RUMAutoInstrumentation.instance = nil
    }
#endif
}
