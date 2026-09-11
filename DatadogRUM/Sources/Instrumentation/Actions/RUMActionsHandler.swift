/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@_spi(Internal)
import DatadogInternal

#if !os(watchOS)
import UIKit
#endif

internal protocol RUMActionsHandling: RUMCommandPublisher {
    #if !os(watchOS)
    /// Tracks RUM actions automatically for UIKit and SwiftUI by responding to `UIApplication.sendEvent(application:event:)` being called.
    func notify_sendEvent(application: UIApplication, event: UIEvent)
    /// Tracks the action, then dispatches the event while its originating scene
    /// context is synchronously available to network instrumentation.
    func intercept_sendEvent(
        application: UIApplication,
        event: UIEvent,
        dispatch: () -> Bool
    ) -> Bool
    #endif
    /// Tracks RUM actions manually with SwiftUI view modifiers by being notified from `RUMTapActionModifier`.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable])
    /// Tracks a manually instrumented SwiftUI action in its owning scene.
    func notify_viewModifierTapped(
        actionName: String,
        actionAttributes: [String: Encodable],
        sceneIdentifier: RUMSceneIdentifier?
    )
}

extension RUMActionsHandling {
    #if !os(watchOS)
    func intercept_sendEvent(
        application: UIApplication,
        event: UIEvent,
        dispatch: () -> Bool
    ) -> Bool {
        notify_sendEvent(application: application, event: event)
        return dispatch()
    }
    #endif

    func notify_viewModifierTapped(
        actionName: String,
        actionAttributes: [String: Encodable],
        sceneIdentifier: RUMSceneIdentifier?
    ) {
        notify_viewModifierTapped(actionName: actionName, actionAttributes: actionAttributes)
    }
}

internal final class RUMActionsHandler: RUMActionsHandling {
    private let dateProvider: DateProvider

    weak var subscriber: RUMCommandSubscriber?

    #if !os(watchOS)
    /// Factory that processes `UIEvents` and creates RUM action commands.
    /// On iOS it also resolves scenes for routing-only event interception, so
    /// it remains non-nil when automatic view tracking enables the swizzler but
    /// both action predicates are disabled.
    private let eventCommandsFactory: UIEventCommandFactory?
    /// Enables the short-lived scene context around UIKit event dispatch.
    /// Ordinary applications keep the original action-only callback path.
    private let isUIEventContextHandoffEnabled: Bool

    /// Convenience initializer for iOS
    convenience init(
        dateProvider: DateProvider,
        heatmapIdentifierRegistry: any HeatmapIdentifierRegistry,
        uiKitPredicate: UITouchRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?,
        isUIEventContextHandoffEnabled: Bool = false
    ) {
        self.init(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: heatmapIdentifierRegistry,
                uiKitPredicate: uiKitPredicate,
                swiftUIPredicate: swiftUIPredicate,
                swiftUIDetector: swiftUIDetector
            ),
            isUIEventContextHandoffEnabled: isUIEventContextHandoffEnabled
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
        eventCommandsFactory: UIEventCommandFactory?,
        isUIEventContextHandoffEnabled: Bool = false
    ) {
        self.eventCommandsFactory = eventCommandsFactory
        self.isUIEventContextHandoffEnabled = isUIEventContextHandoffEnabled
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
    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        _ = process(event: event)
    }

    func intercept_sendEvent(
        application: UIApplication,
        event: UIEvent,
        dispatch: () -> Bool
    ) -> Bool {
        let processedEvent = process(event: event)
        guard isUIEventContextHandoffEnabled,
              let target = processedEvent.target,
              case let .scene(sceneIdentifier) = target else {
            return dispatch()
        }

        let snapshotProvider = subscriber as? RUMContextSnapshotProviding
        let initialContext = snapshotProvider?.rumContextSnapshot(
            for: target,
            at: dateProvider.now
        )
        let excludedUserActionID = processedEvent.didPublishAction
            ? initialContext?.userActionID
            : nil
        let resolver = RUMUIEventContextResolver(
            snapshotProvider: snapshotProvider,
            target: target,
            dateProvider: dateProvider,
            excludedUserActionID: excludedUserActionID
        )
        let synchronousContext = processedEvent.didPublishAction
            ? initialContext.map { $0.replacingUserActionID(with: nil) }
            : initialContext
        return RUMUIEventNetworkContext.withValue(
            sceneIdentifier: sceneIdentifier,
            rumContext: synchronousContext,
            contextProvider: { resolver.currentContext() },
            hasPendingUserAction: processedEvent.didPublishAction,
            excludedUserActionID: excludedUserActionID,
            dispatch
        )
    }

    private struct ProcessedUIEvent {
        let target: RUMCommandTarget?
        let didPublishAction: Bool
    }

    private func process(event: UIEvent) -> ProcessedUIEvent {
        guard let result = eventCommandsFactory?.result(from: event) else {
            return ProcessedUIEvent(target: nil, didPublishAction: false)
        }
        guard let command = result.command else {
            return ProcessedUIEvent(target: result.target, didPublishAction: false)
        }

        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM action was detected, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before any actions are triggered.
                """
            )
            return ProcessedUIEvent(target: result.target, didPublishAction: false)
        }

        subscriber.process(command: command)
        return ProcessedUIEvent(target: result.target, didPublishAction: true)
    }
    #endif

    /// Tracks manually instrumented SwiftUI actions via `.trackRUMTapAction()` view modifier,
    /// in response to `SwiftUI.TapGesture.onEnded` event.
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable]) {
        notify_viewModifierTapped(
            actionName: actionName,
            actionAttributes: actionAttributes,
            sceneIdentifier: nil
        )
    }

    func notify_viewModifierTapped(
        actionName: String,
        actionAttributes: [String: Encodable],
        sceneIdentifier: RUMSceneIdentifier?
    ) {
        var command = RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: actionAttributes,
            instrumentation: .swiftui,
            actionType: .tap,
            name: actionName
        )
        command.target = sceneIdentifier.map(RUMCommandTarget.scene) ?? .processRepresentative

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

#if !os(watchOS)
/// Thread-scoped handoff used only while UIKit dispatches a concrete UI event.
/// It prevents a request synchronously created by scene B's target-action code
/// from inheriting scene A's eventually-consistent process context.
internal enum RUMUIEventNetworkContext {
    static var currentRUMContext: RUMCoreContext? {
        RUMContextHandoff.current?.rumContext
    }

    static var currentSceneIdentifier: RUMSceneIdentifier? {
        RUMContextHandoff.current?.sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    static func withValue<T>(
        sceneIdentifier: RUMSceneIdentifier,
        rumContext: RUMCoreContext?,
        contextProvider: (() -> RUMCoreContext?)? = nil,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil,
        _ block: () -> T
    ) -> T {
        let provider = contextProvider ?? { rumContext }
        return RUMContextHandoff.withValue(
            rumContextProvider: provider,
            sceneIdentifier: sceneIdentifier.rawValue,
            hasPendingUserAction: hasPendingUserAction,
            excludedUserActionID: excludedUserActionID
        ) {
            block()
        }
    }
}

private final class RUMUIEventContextResolver {
    weak var snapshotProvider: RUMContextSnapshotProviding?
    let target: RUMCommandTarget
    let dateProvider: DateProvider
    let excludedUserActionID: String?

    init(
        snapshotProvider: RUMContextSnapshotProviding?,
        target: RUMCommandTarget,
        dateProvider: DateProvider,
        excludedUserActionID: String?
    ) {
        self.snapshotProvider = snapshotProvider
        self.target = target
        self.dateProvider = dateProvider
        self.excludedUserActionID = excludedUserActionID
    }

    func currentContext() -> RUMCoreContext? {
        guard let context = snapshotProvider?.rumContextSnapshot(
            for: target,
            at: dateProvider.now
        ) else {
            return nil
        }
        guard let excludedUserActionID,
              context.userActionID == excludedUserActionID else {
            return context
        }
        return context.replacingUserActionID(with: nil)
    }
}

private extension RUMCoreContext {
    func replacingUserActionID(with userActionID: String?) -> RUMCoreContext {
        RUMCoreContext(
            applicationID: applicationID,
            sessionID: sessionID,
            sessionSampler: sessionSampler,
            viewID: viewID,
            userActionID: userActionID,
            viewServerTimeOffset: viewServerTimeOffset,
            viewPath: viewPath,
            viewName: viewName
        )
    }
}
#endif
