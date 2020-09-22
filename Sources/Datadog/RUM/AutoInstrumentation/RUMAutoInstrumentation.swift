/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// RUM Auto Instrumentation feature.
internal class RUMAutoInstrumentation {
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

    let views: Views?
    // TODO: RUMM-717 Add UserActions instrumentation
    // TODO: RUMM-718 Add Resources instrumentation

    // MARK: - Initialization

    init?(
        configuration: FeaturesConfiguration.RUM.AutoInstrumentation,
        dateProvider: DateProvider
    ) {
        do {
            views = try configuration.uiKitRUMViewsPredicate.flatMap { predicate in
                try Views(uiKitRUMViewsPredicate: predicate, dateProvider: dateProvider)
            }
        } catch {
            userLogger.warn("🔥 RUM automatic tracking can't be set up due to error: \(error)")
            developerLogger?.warn("🔥 RUM automatic tracking can't be set up due to error: \(error)")
            return nil
        }
    }

    func enable() {
        views?.enable()
    }

    func subscribe(commandSubscriber: RUMCommandSubscriber) {
        views?.handler.subscribe(commandsSubscriber: commandSubscriber)
        // TODO: RUMM-717 Pass the weak reference to `commandSubscriber` to `UIKitRUMUserActionsHandler`
        // TODO: RUMM-718 Pass the weak reference to `commandSubscriber` to `UIKitRUMResourceHandler`
    }
}
