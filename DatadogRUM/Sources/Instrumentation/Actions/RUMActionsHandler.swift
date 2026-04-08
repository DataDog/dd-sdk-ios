/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import UIKit
import DatadogInternal

internal protocol RUMActionsHandling: RUMCommandPublisher {
    /// Tracks RUM actions automatically for UIKit and SwiftUI by responding to `UIApplication.sendEvent(application:event:)` being called.
    func notify_sendEvent(application: UIApplication, event: UIEvent)
    /// Tracks RUM actions manually with SwiftUI view modifers by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])
}

internal final class RUMActionsHandler: RUMActionsHandling {
    /// Factory that processes `UIEvents` and creates RUM action commands.
    /// It is `nil` when both UIKit and SwiftUI automatic instrumentations are not enabled.
    private let eventCommandsFactory: UIEventCommandFactory?
    private let dateProvider: DateProvider

    weak var subscriber: RUMCommandSubscriber?

    /// Convenience initializer for iOS
    convenience init(
        dateProvider: DateProvider,
        uiKitPredicate: UITouchRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?
    ) {
        guard uiKitPredicate != nil || swiftUIPredicate != nil else {
            self.init(dateProvider: dateProvider, eventCommandsFactory: nil)
            return
        }

        self.init(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                uiKitPredicate: uiKitPredicate,
                swiftUIPredicate: swiftUIPredicate,
                swiftUIDetector: swiftUIDetector
            )
        )
    }

    /// Convenience initializer for tvOS
    ///
    /// Note: On tvOS, user interactions come through the remote's physical buttons
    /// as press events. These press events are processed at the system level
    /// and delivered identically regardless of whether the UI is built with UIKit or SwiftUI.
    /// Therefore, only one predicate is needed to handle actions from both frameworks.
    convenience init(
        dateProvider: DateProvider,
        uiKitPredicate: UIPressRUMActionsPredicate?
    ) {
        guard let uiKitPredicate else {
            self.init(dateProvider: dateProvider, eventCommandsFactory: nil)
            return
        }

        self.init(
            dateProvider: dateProvider,
            eventCommandsFactory: UIPressCommandFactory(
                dateProvider: dateProvider,
                uiKitPredicate: uiKitPredicate
            )
        )
    }

    init(
        dateProvider: DateProvider,
        eventCommandsFactory: UIEventCommandFactory?
    ) {
        self.eventCommandsFactory = eventCommandsFactory
        self.dateProvider = dateProvider
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    /// Tracks RUM actions automatically for UIKit and SwiftUI in response to `UIApplication.sendEvent(application:event:)` event.
    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        guard let command = eventCommandsFactory?.command(from: event) else {
            return // Not a "tap" event or doesn't have the view.
        }

        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM action was detected, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before any actions are triggered.
                """
            )
            return
        }

        subscriber.process(command: command)
    }

    /// Tracks manually instrumented SwiftUI actions via `.trackRUMTapAction()` view modifier,
    /// in response to `SwiftUI.TapGesture.onEnded` event.
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
#endif
