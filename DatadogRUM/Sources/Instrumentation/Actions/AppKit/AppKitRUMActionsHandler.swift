/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

internal protocol RUMActionsHandling: RUMCommandPublisher {
    /// Tracks RUM actions manually with SwiftUI view modifers by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])

    func notify_sendAction(control: NSControl, action: Selector?, target: Any?)

    func notify_sendEvent(event: NSEvent)
}

internal final class RUMActionsHandler: RUMActionsHandling {
    /// Factory that processes `DDEvents` and creates RUM action commands.
    /// It is `nil` when both UIKit and SwiftUI automatic instrumentations are not enabled.
    private let eventCommandsFactory: AppKitEventCommandFactory?
    private let dateProvider: DateProvider

    weak var subscriber: RUMCommandSubscriber?

    /// Convenience initializer for macOS
    convenience init(
        dateProvider: DateProvider,
        appKitPredicate: AppKitRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?
    ) {
        guard appKitPredicate != nil || swiftUIPredicate != nil else {
            self.init(dateProvider: dateProvider, eventCommandsFactory: nil)
            return
        }

        self.init(
            dateProvider: dateProvider,
            eventCommandsFactory: AppKitCommandFactory(
                dateProvider: dateProvider,
                appKitPredicate: appKitPredicate,
                swiftUIPredicate: swiftUIPredicate,
                swiftUIDetector: swiftUIDetector
            )
        )
    }

    init(
        dateProvider: DateProvider,
        eventCommandsFactory: AppKitCommandFactory?
    ) {
        self.eventCommandsFactory = eventCommandsFactory
        self.dateProvider = dateProvider
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    func notify_sendEvent(event: NSEvent) {
        guard let command = eventCommandsFactory?.command(from: event) else {
            return
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

    func notify_sendAction(control: NSControl, action: Selector?, target: Any?) {
        guard let command = eventCommandsFactory?.command(from: control, action: action, target: target) else {
            return
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
}
#endif
