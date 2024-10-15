/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

internal protocol RUMActionsHandling: RUMCommandPublisher {
    /// Tracks RUM actions in UIKit by responding to `UIApplication.sendEvent(applicatoin:event:)` being called.
    func notify_sendEvent(application: UIApplication, event: UIEvent)
    /// Tracks RUM actions in SwiftUI by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])
}

internal final class RUMActionsHandler: RUMActionsHandling {
    /// Factory interface creating "add action" commands from UIEvent intercepted in UIKit.
    /// It is `nil` when `UIKit` instrumentation is not enabled.
    private let uiKitCommandsFactory: UIEventCommandFactory?
    private let dateProvider: DateProvider

    weak var subscriber: RUMCommandSubscriber?

    convenience init(dateProvider: DateProvider, predicate: UITouchRUMActionsPredicate?) {
        self.init(
            dateProvider: dateProvider,
            uiKitCommandsFactory: predicate.map { UITouchCommandFactory(dateProvider: dateProvider, predicate: $0) }
        )
    }

    convenience init(dateProvider: DateProvider, predicate: UIPressRUMActionsPredicate?) {
        self.init(
            dateProvider: dateProvider,
            uiKitCommandsFactory: predicate.map { UIPressCommandFactory(dateProvider: dateProvider, predicate: $0) }
        )
    }

    init(dateProvider: DateProvider, uiKitCommandsFactory: UIEventCommandFactory?) {
        self.uiKitCommandsFactory = uiKitCommandsFactory
        self.dateProvider = dateProvider
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    /// Tracks UIKit RUM actions in response to `UIApplication.sendEvent(application:event:)` event.
    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        guard let command = uiKitCommandsFactory?.command(from: event) else {
            return // Not a "tap" event or doesn't have the view.
        }

        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM action was detected in UIKit, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before any actions are triggered.
                """
            )
            return
        }

        subscriber.process(command: command)
    }

    /// Tracks SwiftUI RUM actions in response to `SwiftUI.TapGesture.onEnded` event.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable]) {
        let command = RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: actionAttributes,
            instrumentation: .swiftui,
            actionType: .tap,
            name: actionName
        )

        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM action was detected in SwiftUI, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before any actions are triggered.
                """
            )
            return
        }

        subscriber.process(command: command)
    }
}
