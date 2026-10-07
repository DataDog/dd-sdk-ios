/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Foundation
import DatadogInternal

/// On-only storage reused by SwiftUI without resetting customer content.
@MainActor
internal final class RUMSwiftUIViewTrackingEpoch {
    internal struct Callback {
        fileprivate let binding: RUMSwiftUIViewFoundationBinding
        fileprivate let registrationIdentifier: UUID
    }

    internal final class Session {
        fileprivate let binding: RUMSwiftUIViewFoundationBinding
        fileprivate let registrationIdentifier = UUID()
        let trackingState = RUMViewTrackingState()
        let navigationRegistration: RUMSwiftUINavigationOccurrenceRegistration
        let suppressionState = RUMSwiftUIAutomaticViewSuppressionState()
        var didReceiveInitialSceneIdentifier = false
        fileprivate var registrationFence: RUMSwiftUIViewRegistrationFence?

        @MainActor
        fileprivate init(binding: RUMSwiftUIViewFoundationBinding, holder: RUMSwiftUIViewTrackingEpoch) {
            self.binding = binding
            navigationRegistration = RUMSwiftUINavigationOccurrenceRegistration()
            registrationFence = RUMSwiftUIViewRegistrationFence(
                foundationEpoch: binding.epoch, registrationIdentifier: registrationIdentifier,
                holder: holder, session: self
            )
        }
    }

    private var session: Session?

    /// Call at a fresh boundary using the binding captured by that body evaluation.
    func enter(_ binding: RUMSwiftUIViewFoundationBinding) -> Callback? {
        guard binding.isValid else {
            if let session,
               session.binding.epoch == binding.epoch,
               session.binding.lifetime === binding.lifetime {
                session.registrationFence?.retire()
                session.navigationRegistration.cancel()
                self.session = nil
            }
            return nil
        }
        if session?.binding.epoch != binding.epoch ||
            session?.binding.lifetime !== binding.lifetime {
            session?.registrationFence?.retire()
            session?.navigationRegistration.cancel()
            session = Session(binding: binding, holder: self)
        }
        guard let session else {
            return nil
        }
        return Callback(
            binding: binding,
            registrationIdentifier: session.registrationIdentifier
        )
    }

    /// Every callback rechecks its original foundation and registration before mutation.
    func withSession<Result>(
        for callback: Callback,
        _ operation: (Session) -> Result
    ) -> Result? {
        guard callback.binding.isValid else {
            retire(callback)
            return nil
        }
        guard let session,
              session.binding.epoch == callback.binding.epoch,
              session.binding.lifetime === callback.binding.lifetime,
              session.registrationIdentifier == callback.registrationIdentifier else {
            return nil
        }
        return operation(session)
    }

    /// A stale callback can retire only its own SDK registration.
    func retire(_ callback: Callback) {
        guard let session,
              session.binding.epoch == callback.binding.epoch,
              session.binding.lifetime === callback.binding.lifetime,
              session.registrationIdentifier == callback.registrationIdentifier else {
            return
        }
        session.registrationFence?.retire()
        session.navigationRegistration.cancel()
        self.session = nil
    }
}

/// Frozen admission for one body evaluation and its retained callbacks.
@MainActor
internal final class RUMSwiftUIViewCallbackAdmission {
    private weak var holder: RUMSwiftUIViewTrackingEpoch?
    private let callback: RUMSwiftUIViewTrackingEpoch.Callback
    let binding: RUMSwiftUIViewFoundationBinding
    let registrationIdentifier: UUID
    let fence: RUMSwiftUIViewRegistrationFence
    private let stateIdentity: ObjectIdentifier

    init?(holder: RUMSwiftUIViewTrackingEpoch, callback: RUMSwiftUIViewTrackingEpoch.Callback) {
        guard let captured = holder.withSession(for: callback, { session in
            session.registrationFence.map { (ObjectIdentifier(session.trackingState), $0) }
        }) ?? nil, captured.1.isActive else { return nil }
        let identity = captured.0
        self.holder = holder
        self.callback = callback
        binding = callback.binding
        registrationIdentifier = callback.registrationIdentifier
        stateIdentity = identity
        fence = captured.1
        _ = holder.withSession(for: callback) { session in
            session.trackingState.bindAdmission(self)
            session.suppressionState.bindAdmission(self)
        }
    }

    var isValid: Bool {
        guard fence.isActive else { return false }
        return holder?.withSession(for: callback, {
            ObjectIdentifier($0.trackingState) == stateIdentity && $0.registrationFence === fence
        }) == true
    }

    func matches(_ other: RUMSwiftUIViewCallbackAdmission) -> Bool {
        isValid && other.isValid
            && binding.epoch == other.binding.epoch
            && binding.lifetime === other.binding.lifetime
            && registrationIdentifier == other.registrationIdentifier
            && stateIdentity == other.stateIdentity
    }

    func withSession<Result>(_ operation: (RUMSwiftUIViewTrackingEpoch.Session) -> Result) -> Result? {
        guard let holder, isValid else { return nil }
        return holder.withSession(for: callback, operation)
    }

    var foundation: RUMSwiftUIViewFoundation? {
        guard isValid else { return nil }
        return binding.foundation
    }

    func admits(sceneIdentifier: RUMSceneIdentifier) -> Bool {
        guard let foundation else { return false }
        return foundation.admitsConnectedScene(sceneIdentifier, binding: binding)
    }
}
#endif
