/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI)
import Combine
import SwiftUI
import DatadogInternal
#if os(iOS)
import UIKit
#endif

#if os(iOS)
#if os(iOS)
private protocol RUMSwiftUIAutomaticViewAuthorityState: AnyObject {
    var isAutomaticViewAuthorityActive: Bool { get }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

extension RUMViewTrackingState: RUMSwiftUIAutomaticViewAuthorityState {
    fileprivate var isAutomaticViewAuthorityActive: Bool { isAppeared }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

/// Keeps automatic SwiftUI discovery suppressed for a mounted semantic
/// presentation subtree without publishing a second RUM view lifecycle. The
/// navigation owner remains responsible for starting and stopping the semantic
/// occurrence; this state follows the platform subtree through its dismissal.
internal final class RUMSwiftUIAutomaticViewSuppressionState: RUMSwiftUIAutomaticViewAuthorityState {
    private(set) var isActive = false
    private(set) var admission: RUMSwiftUIViewCallbackAdmission?

    @MainActor
    func bindAdmission(_ admission: RUMSwiftUIViewCallbackAdmission) {
        guard admission.isValid, self.admission == nil else { return }
        self.admission = admission
    }

    fileprivate var isAutomaticViewAuthorityActive: Bool { isActive }

    @MainActor
    func appear() {
        guard admission?.isValid == true else { return }
        isActive = true
    }

    @MainActor
    func disappear() {
        guard admission?.isValid == true else { return }
        isActive = false
    }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

/// Tracks active explicit SwiftUI view boundaries so automatic controller
/// discovery can stay enabled without creating a duplicate RUM view for the
/// same subtree. Entries are weak and scoped by actual view containment rather
/// than by scene, leaving unrelated containers in the same window eligible for
/// automatic tracking.
internal final class RUMSwiftUIViewAuthorityRegistry {
    private final class WeakEntry {
        weak var observer: RUMSceneIdentifierReader.ObserverView?
        weak var authorityState: (any RUMSwiftUIAutomaticViewAuthorityState)?
        let fence: RUMSwiftUIViewRegistrationFence

        @MainActor
        init(
            observer: RUMSceneIdentifierReader.ObserverView,
            authorityState: any RUMSwiftUIAutomaticViewAuthorityState,
            admission: RUMSwiftUIViewCallbackAdmission
        ) {
            self.observer = observer
            self.authorityState = authorityState
            self.fence = admission.fence
        }
    }

    private var entries: [WeakEntry] = []

    /// Clears local weak bookkeeping without inspecting or publishing UI state.
    @MainActor
    func removeAll() {
        guard Thread.isMainThread else { return }
        entries.removeAll()
    }

    @MainActor
    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        trackingState: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        register(observer: observer, authorityState: trackingState, admission: admission)
    }

    @MainActor
    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        suppressionState: RUMSwiftUIAutomaticViewSuppressionState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        register(observer: observer, authorityState: suppressionState, admission: admission)
    }

    @MainActor
    private func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        authorityState: any RUMSwiftUIAutomaticViewAuthorityState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard Thread.isMainThread, admission.isValid,
              let sceneIdentifier = observer.currentSceneIdentifier,
              admission.admits(sceneIdentifier: sceneIdentifier) else { return }
        entries.removeAll { entry in
            !entry.fence.isActive || entry.observer == nil || entry.authorityState == nil || entry.observer === observer
        }
        entries.append(WeakEntry(observer: observer, authorityState: authorityState, admission: admission))
    }

    func isAutomaticViewSuppressed(for viewController: UIViewController) -> Bool {
        guard Thread.isMainThread else { return false }
        entries.removeAll { !$0.fence.isActive || $0.observer == nil || $0.authorityState == nil }
        guard let candidateView = viewController.viewIfLoaded else {
            return false
        }

        return entries.contains { entry in
            guard
                entry.fence.isActive,
                entry.authorityState?.isAutomaticViewAuthorityActive == true,
                let observer = entry.observer,
                observer.window != nil
            else {
                return false
            }
            return observer.isDescendant(of: candidateView)
        }
    }
}
#endif // os(iOS)
#endif // os(iOS)

#endif // canImport(SwiftUI)
