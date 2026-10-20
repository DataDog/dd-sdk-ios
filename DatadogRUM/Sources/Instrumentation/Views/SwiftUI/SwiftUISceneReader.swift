/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Foundation
import SwiftUI
import UIKit
@_spi(Internal)
import DatadogInternal

@available(iOS 17.0, *)
internal enum RUMSceneIdentifierTrait: UITraitDefinition {
    static let defaultValue: String? = nil
    static let identifier = "com.datadoghq.rum.scene-identifier"
}

/// Publishes scene identity only for its originating registered SwiftUI foundation.
@available(iOS 17.0, *)
internal final class RUMSceneIdentifierTraitPublisher: NSObject {
    private weak var notificationCenter: NotificationCenter?
    private weak var handler: RUMSceneViewsHandler?
    private weak var monitor: Monitor?
    private let lifetime: RUMSwiftUIViewLifetime
    private let admitsFoundation: @MainActor () -> Bool

    @MainActor
    init?(
        notificationCenter: NotificationCenter,
        handler: RUMSceneViewsHandler,
        lifetime: RUMSwiftUIViewLifetime,
        admitsFoundation: @escaping @MainActor () -> Bool
    ) {
        guard admitsFoundation(), lifetime.isValid(for: handler),
              let monitor = handler.subscriber as? Monitor else {
            return nil
        }
        self.notificationCenter = notificationCenter
        self.handler = handler
        self.monitor = monitor
        self.lifetime = lifetime
        self.admitsFoundation = admitsFoundation
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(sceneWillConnect(_:)),
            name: UIScene.willConnectNotification,
            object: nil
        )
        seedConnectedScenes()
    }

    deinit {
        notificationCenter?.removeObserver(
            self,
            name: UIScene.willConnectNotification,
            object: nil
        )
    }

    // UIKit acquisition and mutation stay behind the existing main-thread boundary.
    @MainActor
    private func admitsPublication() -> Bool {
        guard Thread.isMainThread, admitsFoundation(),
              let handler,
              let monitor,
              lifetime.isValid(for: monitor),
              (handler.subscriber as? Monitor) === monitor else {
            return false
        }
        return true
    }

    @objc
    private func sceneWillConnect(_ notification: Notification) {
        weak var scene = notification.object as? UIWindowScene
        DispatchQueue.main.async { [weak self, weak scene] in
            guard let self, self.admitsPublication(), let scene else { return }
            self.seed(scene)
        }
    }

    @MainActor
    private func seedConnectedScenes() {
        guard Thread.isMainThread else {
            scheduleConnectedSceneSeed()
            return
        }
        guard admitsPublication() else {
            return
        }
        UIApplication.dd.managedShared?.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach(seed)
    }

    private func scheduleConnectedSceneSeed() {
        DispatchQueue.main.async { [weak self] in
            self?.seedConnectedScenes()
        }
    }

    @MainActor
    private func seed(_ scene: UIWindowScene) {
        guard admitsPublication() else {
            return
        }
        scene.traitOverrides[RUMSceneIdentifierTrait.self] = scene.session.persistentIdentifier
    }
}

#if os(iOS)

/// Resolves the `UIWindowScene` hosting a SwiftUI view without exposing UIKit in
/// the public modifier API. When UIKit's scene trait has already bridged into the
/// SwiftUI environment, the reader can report that scene while creating its
/// platform view. The attachment callbacks remain a fail-safe for delayed trait
/// propagation and scene changes.
internal struct RUMSceneIdentifierReader: UIViewRepresentable {
    let admission: RUMSwiftUIViewCallbackAdmission
    let applicationSupportsMultipleScenes: Bool
    let initialSceneIdentifier: RUMSceneIdentifier?
    let onCreate: (@MainActor (ObserverView) -> Void)?
    let onInitialMount: (@MainActor (RUMSceneIdentifier) -> Void)?
    let onMount: (@MainActor (RUMSceneIdentifier) -> Void)?
    let onReconcile: (@MainActor (RUMViewTrackingState.Attachment) -> Void)?
    let onChange: @MainActor (RUMViewTrackingState.Attachment) -> Void

    @MainActor
    init(
        admission: RUMSwiftUIViewCallbackAdmission,
        applicationSupportsMultipleScenes: Bool,
        initialSceneIdentifier: RUMSceneIdentifier? = nil,
        onCreate: (@MainActor (ObserverView) -> Void)? = nil,
        onInitialMount: (@MainActor (RUMSceneIdentifier) -> Void)? = nil,
        onMount: (@MainActor (RUMSceneIdentifier) -> Void)? = nil,
        onReconcile: (@MainActor (RUMViewTrackingState.Attachment) -> Void)? = nil,
        onChange: @escaping @MainActor (RUMViewTrackingState.Attachment) -> Void
    ) {
        self.admission = admission
        self.applicationSupportsMultipleScenes = applicationSupportsMultipleScenes
        self.initialSceneIdentifier = initialSceneIdentifier
        self.onCreate = onCreate
        self.onInitialMount = onInitialMount
        self.onMount = onMount
        self.onReconcile = onReconcile
        self.onChange = onChange
    }

    static func attachment(
        isAttachedToWindow: Bool,
        sceneIdentifier: RUMSceneIdentifier?,
        applicationSupportsMultipleScenes: Bool,
        isSceneConnected: Bool = true
    ) -> RUMViewTrackingState.Attachment {
        if let sceneIdentifier, isSceneConnected {
            return .attached(sceneIdentifier)
        }
        return .detached
    }

    @MainActor
    func makeUIView(context: Context) -> ObserverView {
        let observer = ObserverView(
            admission: admission,
            onChange: onChange,
            onMount: onMount,
            applicationSupportsMultipleScenes: applicationSupportsMultipleScenes
        )
        guard admission.isValid else { return observer }
        onCreate?(observer)
        if let initialSceneIdentifier, admission.admits(sceneIdentifier: initialSceneIdentifier) {
            onInitialMount?(initialSceneIdentifier)
        }
        return observer
    }

    @MainActor
    func updateUIView(_ uiView: ObserverView, context: Context) {
        update(observer: uiView)
    }

    /// Rebinds a representable reused by SwiftUI. Registration is idempotent,
    /// and the resolved mount callback intentionally runs even when the scene
    /// attachment value is unchanged after a disconnect/reconnect cycle.
    @MainActor
    func update(observer: ObserverView) {
        guard admission.isValid else { return }
        observer.rebind(admission: admission)
        onCreate?(observer)
        observer.onMount = onMount
        observer.onChange = onChange
        onReconcile?(observer.currentAttachment)
        observer.notifyCurrentAttachment()
    }

    final class ObserverView: UIView {
        private var admission: RUMSwiftUIViewCallbackAdmission?
        var onChange: @MainActor (RUMViewTrackingState.Attachment) -> Void
        var onMount: (@MainActor (RUMSceneIdentifier) -> Void)?
        private var lastAttachment: RUMViewTrackingState.Attachment?
        private var requiresMountNotification = false
        private var lastProvenSceneIdentifier: RUMSceneIdentifier?
        private let applicationSupportsMultipleScenes: Bool

        init(
            admission: RUMSwiftUIViewCallbackAdmission,
            onChange: @escaping @MainActor (RUMViewTrackingState.Attachment) -> Void,
            onMount: (@MainActor (RUMSceneIdentifier) -> Void)? = nil,
            applicationSupportsMultipleScenes: Bool = false
        ) {
            self.admission = admission
            self.onChange = onChange
            self.onMount = onMount
            self.applicationSupportsMultipleScenes = applicationSupportsMultipleScenes
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) {
            self.admission = nil
            self.onChange = { _ in }
            self.onMount = nil
            self.applicationSupportsMultipleScenes = false
            super.init(coder: coder)
            isUserInteractionEnabled = false
            isHidden = true
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            notifyCurrentAttachment()
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            // Report attachment after UIKit assigns window; preserve early detach.
            if newWindow == nil {
                notify(window: nil)
            }
            super.willMove(toWindow: newWindow)
        }

        func notifyCurrentAttachment() {
            notify(attachment: currentAttachment(for: window))
        }

        fileprivate func notify(window: UIWindow?) {
            notify(attachment: currentAttachment(for: window))
        }

        func rebind(admission: RUMSwiftUIViewCallbackAdmission) {
            guard admission.isValid else { return }
            if self.admission.map({ $0.matches(admission) }) != true {
                lastAttachment = nil
                requiresMountNotification = false
                lastProvenSceneIdentifier = nil
            }
            self.admission = admission
        }

        func notify(attachment: RUMViewTrackingState.Attachment) {
            guard let admission, admission.isValid else { return }
            if case .attached(let scene) = attachment {
                guard let scene, admission.admits(sceneIdentifier: scene) else { return }
            }
            if case .attached(let sceneIdentifier) = attachment, let sceneIdentifier {
                lastProvenSceneIdentifier = sceneIdentifier
                if attachment != lastAttachment || requiresMountNotification {
                    requiresMountNotification = false
                    onMount?(sceneIdentifier)
                }
            }
            guard attachment != lastAttachment else {
                return
            }
            lastAttachment = attachment
            onChange(attachment)
        }

        func markSceneDisconnected(_ sceneIdentifier: RUMSceneIdentifier) {
            guard admission?.isValid == true else { return }
            guard lastProvenSceneIdentifier == sceneIdentifier else {
                return
            }
            lastAttachment = .detached
            requiresMountNotification = true
        }

        var lastSceneIdentifier: RUMSceneIdentifier? {
            lastProvenSceneIdentifier
        }

        var currentSceneIdentifier: RUMSceneIdentifier? {
            guard case .attached(let sceneIdentifier) = currentAttachment(for: window) else {
                return nil
            }
            return sceneIdentifier
        }

        var currentAttachment: RUMViewTrackingState.Attachment {
            currentAttachment(for: window)
        }

        private func currentAttachment(for window: UIWindow?) -> RUMViewTrackingState.Attachment {
            guard admission?.isValid == true else { return .detached }
            let windowScene = window?.windowScene
            let sceneIdentifier = (windowScene?.session.persistentIdentifier)
                .map { RUMSceneIdentifier(rawValue: $0) }
            return RUMSceneIdentifierReader.attachment(
                isAttachedToWindow: window != nil,
                sceneIdentifier: sceneIdentifier,
                applicationSupportsMultipleScenes: applicationSupportsMultipleScenes,
                isSceneConnected: windowScene?.activationState != .unattached
            )
        }

        #if os(iOS)
        var nearestViewController: UIViewController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let viewController = current as? UIViewController {
                    return viewController
                }
                responder = current.next
            }
            return nil
        }
        #endif
    }
}
#endif // os(iOS)

#if os(iOS)

/// Reference-backed scene state used by SwiftUI action modifiers.
internal final class RUMSceneTrackingState {
    private let admission: RUMSwiftUIViewCallbackAdmission
    @MainActor init(admission: RUMSwiftUIViewCallbackAdmission) { self.admission = admission }
    private(set) var sceneIdentifier: RUMSceneIdentifier?

    @MainActor
    func update(attachment: RUMViewTrackingState.Attachment) {
        guard admission.isValid else { return }
        if case .attached(let scene) = attachment {
            guard let scene, admission.admits(sceneIdentifier: scene) else { return }
        }
        switch attachment {
        case .detached:
            sceneIdentifier = nil
        case .attached(let sceneIdentifier):
            self.sceneIdentifier = sceneIdentifier
        }
    }
}
#endif // os(iOS)

#endif // canImport(SwiftUI)
