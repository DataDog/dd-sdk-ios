/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit)
#if !os(watchOS)
import UIKit
#endif
@_spi(Internal)
import DatadogInternal

internal protocol RUMActionsHandling: RUMCommandPublisher {
    #if !os(watchOS)
    /// Tracks RUM actions automatically for UIKit and SwiftUI by responding to `UIApplication.sendEvent(application:event:)` being called.
    func notify_sendEvent(application: UIApplication, event: DDEvent)
    #endif
    /// Tracks RUM actions manually with SwiftUI view modifiers by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])
}

internal final class RUMActionsHandler: RUMActionsHandling {
    private let dateProvider: DateProvider

    weak var subscriber: RUMCommandSubscriber?

    #if !os(watchOS)
    /// Factory that processes `UIEvents` and creates RUM action commands.
    /// It is `nil` when both UIKit and SwiftUI automatic instrumentations are not enabled.
    private let eventCommandsFactory: UIEventCommandFactory?

    /// Convenience initializer for iOS
    convenience init(
        dateProvider: DateProvider,
        heatmapIdentifierRegistry: any HeatmapIdentifierRegistry,
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
                heatmapIdentifierRegistry: heatmapIdentifierRegistry,
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

    init(dateProvider: DateProvider, eventCommandsFactory: UIEventCommandFactory?) {
        self.eventCommandsFactory = eventCommandsFactory
        self.dateProvider = dateProvider
    }
    #else
    init(dateProvider: DateProvider) {
        self.dateProvider = dateProvider
    }
    #endif

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    #if !os(watchOS)
    /// Tracks RUM actions automatically for UIKit and SwiftUI in response to `UIApplication.sendEvent(application:event:)` event.
    func notify_sendEvent(application: DDApplication, event: DDEvent) {
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
    #endif

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

#if os(iOS)
/// Encloses the original UIKit delivery in scene-owned action context.
@available(iOS 27.0, *)
internal protocol RUMSceneActionsHandling: RUMActionsHandling {
    func intercept(application: UIApplication, event: UIEvent, operation: () -> Void)
}

/// Publishes automatic touch actions using ownership captured before customer predicates.
@available(iOS 27.0, *)
internal final class RUMSceneActionsHandler: RUMSceneActionsHandling {
    private let legacyHandler: RUMActionsHandler
    private let eventCommandsFactory: UIEventCommandFactory?
    private let dateProvider: DateProvider
    private let owner: RUMContextHandoff.Owner
    private weak var expectedMonitor: Monitor?
    private weak var subscriber: RUMCommandSubscriber?
    private let sceneIdentifier: (UIWindow) -> RUMSceneIdentifier?

    init(
        legacyHandler: RUMActionsHandler,
        eventCommandsFactory: UIEventCommandFactory?,
        dateProvider: DateProvider,
        owner: RUMContextHandoff.Owner,
        expectedMonitor: Monitor,
        sceneIdentifier: @escaping (UIWindow) -> RUMSceneIdentifier? = {
            $0.windowScene.map { RUMSceneIdentifier(rawValue: $0.session.persistentIdentifier) }
        }
    ) {
        self.legacyHandler = legacyHandler
        self.eventCommandsFactory = eventCommandsFactory
        self.dateProvider = dateProvider
        self.owner = owner
        self.expectedMonitor = expectedMonitor
        self.sceneIdentifier = sceneIdentifier
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
        legacyHandler.publish(to: subscriber)
    }

    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable]) {
        legacyHandler.notify_viewModifierTapped(actionName: actionName, actionAttributes: actionAttributes)
    }

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        intercept(application: application, event: event, operation: {})
    }

    func intercept(application: UIApplication, event: UIEvent, operation: () -> Void) {
        guard let identifier = sourceSceneIdentifier(for: event) else {
            // No new binding: a nested source-less event preserves its inherited context.
            legacyHandler.notify_sendEvent(application: application, event: event)
            operation()
            return
        }

        let captured = RUMContextHandoff.CurrentValue(
            rumContext: snapshot(for: identifier),
            sceneIdentifier: identifier.rawValue,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        RUMContextHandoff.withValue(captured, for: owner) {
            guard var command = eventCommandsFactory?.command(from: event), isOwnedSubscriber else {
                operation()
                return
            }
            command.target = .scene(identifier)
            // Pending denotes a selected command awaiting processing, not an Action UUID.
            let pending = RUMContextHandoff.CurrentValue(
                rumContext: captured.rumContext,
                sceneIdentifier: captured.sceneIdentifier,
                hasPendingUserAction: true,
                excludedUserActionID: captured.rumContext?.userActionID
            )
            let didPublish = RUMContextHandoff.withValue(pending, for: owner) {
                guard publishIfOwned(command) else {
                    return false
                }
                operation()
                return true
            }
            if !didPublish {
                operation()
            }
        }
    }

    private func sourceSceneIdentifier(for event: UIEvent) -> RUMSceneIdentifier? {
        guard let touches = event.allTouches, touches.count == 1,
              let touch = touches.first, let window = touch.window ?? touch.view?.window else {
            return nil
        }
        // A nonnil original window without a scene must not borrow the view's new window.
        return sceneIdentifier(window)
    }

    private var isOwnedSubscriber: Bool {
        guard owner.isValid, let monitor = expectedMonitor, subscriber === monitor else {
            return false
        }
        return monitor.isMultiSceneTrackingEnabled && monitor.rumContextHandoffOwner === owner
    }

    private func snapshot(for identifier: RUMSceneIdentifier) -> RUMCoreContext? {
        guard owner.isValid, let monitor = expectedMonitor, subscriber === monitor,
              monitor.isMultiSceneTrackingEnabled, monitor.rumContextHandoffOwner === owner else {
            return nil
        }
        return monitor.rumContextSnapshot(for: .scene(identifier), at: dateProvider.now)
    }

    private func publishIfOwned(_ command: RUMAddUserActionCommand) -> Bool {
        guard owner.isValid, let monitor = expectedMonitor, subscriber === monitor,
              monitor.isMultiSceneTrackingEnabled, monitor.rumContextHandoffOwner === owner else {
            return false
        }
        monitor.process(command: command)
        return true
    }
}
#endif
