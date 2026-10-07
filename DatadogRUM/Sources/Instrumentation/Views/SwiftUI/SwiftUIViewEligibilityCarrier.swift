/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Foundation
import UIKit

/// Synchronous eligibility only. Actual publication keeps the actor Callback proof.
internal final class RUMSwiftUIViewRegistrationFence {
    let foundationEpoch: UUID
    let registrationIdentifier: UUID
    private weak var holder: AnyObject?
    private weak var session: AnyObject?
    private var retired = false

    @MainActor
    init(foundationEpoch: UUID, registrationIdentifier: UUID, holder: AnyObject, session: AnyObject) {
        self.foundationEpoch = foundationEpoch
        self.registrationIdentifier = registrationIdentifier
        self.holder = holder
        self.session = session
    }

    var isActive: Bool {
        guard Thread.isMainThread else { return false }
        return !retired && holder != nil && session != nil
    }

    func retire() {
        guard Thread.isMainThread else { return }
        retired = true
    }
}

internal final class RUMSwiftUIViewEligibilityCarrier {
    private weak var instrumentation: RUMInstrumentation?
    private weak var originalFoundation: AnyObject?
    private weak var handler: RUMSceneViewsHandler?
    private weak var monitor: Monitor?
    private let lifetime: RUMSwiftUIViewLifetime
    private let registry: RUMSwiftUIViewAuthorityRegistry
    private var installed = false
    private var retired = false

    @MainActor
    init(instrumentation: RUMInstrumentation, foundation: AnyObject,
         handler: RUMSceneViewsHandler, monitor: Monitor,
         lifetime: RUMSwiftUIViewLifetime, registry: RUMSwiftUIViewAuthorityRegistry) {
        self.instrumentation = instrumentation
        originalFoundation = foundation
        self.handler = handler
        self.monitor = monitor
        self.lifetime = lifetime
        self.registry = registry
    }

    private func hasOriginalMembership() -> Bool {
        guard Thread.isMainThread else { return false }
        guard let instrumentation, let originalFoundation, let handler, let monitor,
              (instrumentation.swiftUIViewFoundation as AnyObject?) === originalFoundation,
              (instrumentation.viewsHandler as AnyObject) === handler,
              (handler.subscriber as? Monitor) === monitor,
              lifetime.isValid(for: monitor) else { return false }
        return true
    }

    @discardableResult
    func install() -> Bool {
        guard Thread.isMainThread else { return false }
        guard !installed, !retired, hasOriginalMembership() else { return false }
        installed = true
        return true
    }

    func retire() {
        guard Thread.isMainThread else { return }
        retired = true
    }

    func isEligible(_ viewController: UIViewController) -> Bool {
        guard Thread.isMainThread else { return false }
        guard installed, !retired, hasOriginalMembership() else { return false }
        return !registry.isAutomaticViewSuppressed(for: viewController)
    }
}
#endif
