/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import DatadogInternal

internal protocol RUMActionsHandling: RUMCommandPublisher {
    /// Notifies a `.leftMouseDown` event was dispatched through the app's main event loop.
    func notify_sendEvent(event: NSEvent)

    /// Notifies that a menu item was selected and its action was dispatched.
    func notify_menuItemSelected(_ menuItem: NSMenuItem)

    /// Tracks RUM actions manually with AppKit view modifiers by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])
}

internal final class RUMActionsHandler: RUMActionsHandling {
    /// Factory that processes `DDEvents` and creates RUM action commands.
    /// It is `nil` when both AppKit and SwiftUI automatic instrumentations are not enabled.
    private let eventCommandsFactory: AppKitEventCommandFactory?

    /// Provides the date used for the event timestamps.
    private let dateProvider: DateProvider

    /// Subscriber that will process the RUM Commands generated from the user-interface events.
    weak var subscriber: RUMCommandSubscriber?

    /// Initializes the `RUMActionsHandler`.
    ///
    /// For automatic action tracking, `appKitPredicate` and/or `swiftUIPredicate` must be not `nil`.
    /// If both values are `nil`, only manual tracking is supported.
    ///
    /// - Parameters:
    ///   - dateProvider: The date provider used to timestamp the events.
    ///   - appKitPredicate: Predicate deciding if a RUM action should be recorded for a given event on an AppKit view.
    @MainActor
    convenience init(
        dateProvider: DateProvider,
        appKitPredicate: MacOSRUMActionsPredicate?
    ) {
        guard let appKitPredicate else {
            self.init(dateProvider: dateProvider, eventCommandsFactory: nil)
            return
        }

        self.init(
            dateProvider: dateProvider,
            eventCommandsFactory: AppKitCommandFactory(
                dateProvider: dateProvider,
                macOSPredicate: appKitPredicate,
                accessibilityHierarchyDetector: MacOSAccessibilityHierarchyDetector()
            )
        )
    }

    /// Initializes the `RUMActionsHandler`.
    ///
    /// For automatic action tracking, `eventCommandsFactory` must be not `nil`. Otherwise, only manual tracking is supported.
    ///
    /// - Parameters:
    ///   - dateProvider: The date provider used to timestamp the events.
    ///   - eventCommandsFactory: Factory producing RUM Actions for the given events. Must not be `nil` for automatic event
    ///   tracking to work, otherwise only manual tracking is supported.
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

    func notify_menuItemSelected(_ menuItem: NSMenuItem) {
        guard let command = eventCommandsFactory?.command(from: menuItem) else {
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
