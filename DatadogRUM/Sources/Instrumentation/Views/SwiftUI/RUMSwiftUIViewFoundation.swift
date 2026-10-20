/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Foundation
import UIKit
@_spi(Internal)
import DatadogInternal

/// Owns tracking resources for one successfully registered SwiftUI feature.
@MainActor
internal final class RUMSwiftUIViewFoundation {
    let lifetime: RUMSwiftUIViewLifetime
    let epoch: UUID
    private weak var instrumentation: RUMInstrumentation?
    private weak var handler: RUMSceneViewsHandler?
    private var isActive = false
    private var isRetired = false
    private let authorityRegistry = RUMSwiftUIViewAuthorityRegistry()
    private var transitionArbiter: RUMSwiftUIInteractiveTransitionArbiter?
    private var traitPublisher: AnyObject?
    private var eligibilityCarrier: RUMSwiftUIViewEligibilityCarrier?
    private var notificationCenter: NotificationCenter?

    var sceneLifecycleNotificationCenter: NotificationCenter? {
        isValid ? notificationCenter : nil
    }

    init?(
        instrumentation: RUMInstrumentation,
        handler: RUMSceneViewsHandler,
        lifetime: RUMSwiftUIViewLifetime,
        epoch: UUID
    ) {
        guard (instrumentation.viewsHandler as AnyObject) === handler,
              lifetime.isValid(for: handler) else {
            return nil
        }
        self.instrumentation = instrumentation
        self.handler = handler
        self.lifetime = lifetime
        self.epoch = epoch
    }

    var isValid: Bool {
        guard isActive, !isRetired,
              let instrumentation,
              instrumentation.swiftUIViewFoundation === self,
              let handler else {
            return false
        }
        return (instrumentation.viewsHandler as AnyObject) === handler
            && lifetime.isValid(for: handler)
    }

    func canInstall(in candidate: RUMSceneViewsHandler) -> Bool {
        guard !isActive, !isRetired, let handler, handler === candidate,
              let instrumentation,
              (instrumentation.viewsHandler as AnyObject) === candidate,
              lifetime.isValid(for: candidate) else { return false }
        return true
    }

    /// Activates observers only after the original On handler owns this foundation.
    @discardableResult
    func activate(notificationCenter: NotificationCenter) -> Bool {
        guard !isActive, !isRetired,
              let instrumentation,
              instrumentation.swiftUIViewFoundation === self,
              let handler,
              lifetime.isValid(for: handler) else {
            return false
        }
        guard let monitor = handler.subscriber as? Monitor else { return false }
        let carrier = RUMSwiftUIViewEligibilityCarrier(
            instrumentation: instrumentation, foundation: self,
            handler: handler, monitor: monitor, lifetime: lifetime, registry: authorityRegistry
        )
        guard carrier.install() else { return false }
        eligibilityCarrier = carrier
        self.notificationCenter = notificationCenter
        isActive = true
        transitionArbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            admitsCallbacks: { [weak self] in self?.isValid == true }
        )
        if #available(iOS 17.0, *) {
            guard let publisher = RUMSceneIdentifierTraitPublisher(
                notificationCenter: notificationCenter,
                handler: handler,
                lifetime: lifetime,
                admitsFoundation: { [weak self] in self?.isValid == true }
            ) else {
                retire()
                return false
            }
            traitPublisher = publisher
        }
        guard isValid else {
            retire()
            return false
        }
        return true
    }

    func makeBinding() -> RUMSwiftUIViewFoundationBinding? {
        guard isValid else { return nil }
        return RUMSwiftUIViewFoundationBinding(foundation: self)
    }

    fileprivate func admits(_ binding: RUMSwiftUIViewFoundationBinding) -> Bool {
        isValid && binding.origin === self
            && binding.lifetime === lifetime && binding.epoch == epoch
    }

    /// Invalidates local resources without submitting replacement-feature work.
    func retire() {
        notificationCenter = nil
        eligibilityCarrier?.retire()
        isRetired = true
        isActive = false
        traitPublisher = nil
        transitionArbiter?.cancelPendingWithoutPublishing()
        transitionArbiter = nil
        authorityRegistry.removeAll()
        eligibilityCarrier = nil
    }

    func makeEligibilityCheck() -> ((UIViewController) -> Bool)? {
        guard isValid, let eligibilityCarrier else { return nil }
        return { [weak eligibilityCarrier] viewController in
            eligibilityCarrier?.isEligible(viewController) == true
        }
    }

    func admitsConnectedScene(_ sceneIdentifier: RUMSceneIdentifier,
                              binding: RUMSwiftUIViewFoundationBinding) -> Bool {
        guard admits(binding) else { return false }
        return UIApplication.dd.managedShared?.connectedScenes.contains { scene in
            scene.activationState != .unattached
                && scene.session.persistentIdentifier == sceneIdentifier.rawValue
        } == true
    }

    func registerAuthority(observer: RUMSceneIdentifierReader.ObserverView,
                           trackingState: RUMViewTrackingState,
                           admission: RUMSwiftUIViewCallbackAdmission) {
        guard admission.isValid, admits(admission.binding),
              trackingState.admission?.matches(admission) == true,
              let scene = observer.currentSceneIdentifier,
              admitsConnectedScene(scene, binding: admission.binding) else { return }
        authorityRegistry.register(observer: observer, trackingState: trackingState, admission: admission)
    }

    func registerSuppression(observer: RUMSceneIdentifierReader.ObserverView,
                             suppressionState: RUMSwiftUIAutomaticViewSuppressionState,
                             admission: RUMSwiftUIViewCallbackAdmission) {
        guard admission.isValid, admits(admission.binding),
              suppressionState.admission?.matches(admission) == true,
              let scene = observer.currentSceneIdentifier,
              admitsConnectedScene(scene, binding: admission.binding) else { return }
        authorityRegistry.register(observer: observer, suppressionState: suppressionState, admission: admission)
    }

    func makeTransitionAdmission(for admission: RUMSwiftUIViewCallbackAdmission) -> RUMSwiftUIViewTransitionAdmission? {
        guard admission.isValid, admits(admission.binding), transitionArbiter != nil else { return nil }
        return RUMSwiftUIViewTransitionAdmission(foundation: self, admission: admission)
    }

    fileprivate func registerTransition(observer: RUMSceneIdentifierReader.ObserverView,
                                        state: RUMViewTrackingState,
                                        source: RUMSwiftUINavigationOccurrenceSource?,
                                        admission: RUMSwiftUIViewCallbackAdmission) {
        guard admission.isValid, admits(admission.binding),
              state.admission?.matches(admission) == true,
              let scene = observer.currentSceneIdentifier,
              admitsConnectedScene(scene, binding: admission.binding) else { return }
        transitionArbiter?.register(observer: observer, for: state, navigationOccurrenceSource: source)
    }

    fileprivate func processTransition(_ intent: RUMSwiftUIInteractiveTransitionArbiter.Intent,
                                       state: RUMViewTrackingState,
                                       admission: RUMSwiftUIViewCallbackAdmission,
                                       send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void) {
        guard admission.isValid, admits(admission.binding),
              state.admission?.matches(admission) == true else { return }
        transitionArbiter?.process(intent, state: state) { [weak admission] transitions in
            guard let admission, admission.isValid else { return }
            send(transitions)
        }
    }

    @discardableResult
    func appear(
        identity: String, name: String, path: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier,
        binding: RUMSwiftUIViewFoundationBinding
    ) -> Bool {
        guard admits(binding), let handler else { return false }
        return handler.notify_onAppear(
            identity: identity, name: name, path: path, attributes: attributes,
            sceneIdentifier: sceneIdentifier, lifetime: lifetime
        )
    }

    @discardableResult
    func disappear(
        identity: String, sceneIdentifier: RUMSceneIdentifier,
        binding: RUMSwiftUIViewFoundationBinding
    ) -> Bool {
        guard admits(binding), let handler else { return false }
        return handler.notify_onDisappear(
            identity: identity, attributes: nil,
            sceneIdentifier: sceneIdentifier, lifetime: lifetime
        )
    }

    @discardableResult
    func replace(
        identity: String, newIdentity: String, name: String, path: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier,
        binding: RUMSwiftUIViewFoundationBinding
    ) -> Bool {
        guard admits(binding), let handler else { return false }
        return handler.notify_onReplace(
            identity: identity, newIdentity: newIdentity, name: name, path: path,
            attributes: attributes, sceneIdentifier: sceneIdentifier, lifetime: lifetime
        )
    }
}

/// Carries the original lifetime and epoch without retaining their foundation.
@MainActor
internal final class RUMSwiftUIViewFoundationBinding {
    let lifetime: RUMSwiftUIViewLifetime
    let epoch: UUID
    fileprivate weak var origin: RUMSwiftUIViewFoundation?

    fileprivate init(foundation: RUMSwiftUIViewFoundation) {
        origin = foundation
        lifetime = foundation.lifetime
        epoch = foundation.epoch
    }

    var isValid: Bool { origin?.admits(self) == true }

    var foundation: RUMSwiftUIViewFoundation? {
        guard let origin, origin.admits(self) else { return nil }
        return origin
    }
}
/// A route context can retain this facade without retaining its original foundation.
@MainActor
internal final class RUMSwiftUIViewTransitionAdmission {
    private weak var foundation: RUMSwiftUIViewFoundation?
    private let admission: RUMSwiftUIViewCallbackAdmission

    fileprivate init(foundation: RUMSwiftUIViewFoundation, admission: RUMSwiftUIViewCallbackAdmission) {
        self.foundation = foundation
        self.admission = admission
    }

    func register(observer: RUMSceneIdentifierReader.ObserverView, for state: RUMViewTrackingState,
                  navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource? = nil) {
        guard admission.isValid else { return }
        foundation?.registerTransition(observer: observer, state: state,
                                       source: navigationOccurrenceSource, admission: admission)
    }

    func process(_ intent: RUMSwiftUIInteractiveTransitionArbiter.Intent, state: RUMViewTrackingState,
                 send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void) {
        guard admission.isValid else { return }
        foundation?.processTransition(intent, state: state, admission: admission, send: send)
    }
}
#endif
