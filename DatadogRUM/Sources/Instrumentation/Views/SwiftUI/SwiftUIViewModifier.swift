/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI)
import SwiftUI
import DatadogInternal

#if os(iOS) || os(visionOS)
import UIKit

@available(iOS 17.0, visionOS 1.0, *)
internal enum RUMSceneIdentifierTrait: UITraitDefinition {
    static let defaultValue: String? = nil
    static let identifier = "com.datadoghq.rum.scene-identifier"
}

@available(iOS 17.0, visionOS 1.0, *)
private struct RUMSceneIdentifierEnvironmentKey: UITraitBridgedEnvironmentKey {
    static let defaultValue: String? = nil

    static func read(from traitCollection: UITraitCollection) -> String? {
        traitCollection[RUMSceneIdentifierTrait.self]
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: String?) {
        mutableTraits[RUMSceneIdentifierTrait.self] = value
    }
}

@available(iOS 17.0, visionOS 1.0, *)
private extension EnvironmentValues {
    var rumSceneIdentifier: String? {
        get { self[RUMSceneIdentifierEnvironmentKey.self] }
        set { self[RUMSceneIdentifierEnvironmentKey.self] = newValue }
    }
}

/// Publishes each real scene identifier as an inherited UIKit trait. UIKit
/// bridges the trait into SwiftUI before the hidden attachment reader joins the
/// view hierarchy, allowing RUM to enqueue its view transition from the earliest
/// supported SwiftUI appearance callback. The reader remains a fail-safe for
/// delayed or missing trait propagation.
@available(iOS 17.0, visionOS 1.0, *)
internal final class RUMSceneIdentifierTraitPublisher: NSObject {
    private weak var notificationCenter: NotificationCenter?

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
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

    @objc
    private func sceneWillConnect(_ notification: Notification) {
        guard Thread.isMainThread else {
            scheduleConnectedSceneSeed()
            return
        }
        guard let windowScene = notification.object as? UIWindowScene else {
            return
        }
        seed(windowScene)
    }

    private func seedConnectedScenes() {
        guard Thread.isMainThread else {
            scheduleConnectedSceneSeed()
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

    private func seed(_ scene: UIWindowScene) {
        scene.traitOverrides[RUMSceneIdentifierTrait.self] = scene.session.persistentIdentifier
    }
}

/// Resolves the `UIWindowScene` hosting a SwiftUI view without exposing UIKit in
/// the public modifier API. SwiftUI does not guarantee that this attachment is
/// reported before its appearance callbacks.
internal struct RUMSceneIdentifierReader: UIViewRepresentable {
    let applicationSupportsMultipleScenes: Bool
    let onChange: (RUMViewTrackingState.Attachment) -> Void

    static func attachment(
        isAttachedToWindow: Bool,
        sceneIdentifier: RUMSceneIdentifier?,
        applicationSupportsMultipleScenes: Bool
    ) -> RUMViewTrackingState.Attachment {
        if let sceneIdentifier {
            return .attached(sceneIdentifier)
        }
        if isAttachedToWindow, !applicationSupportsMultipleScenes {
            return .attached(nil)
        }
        return .detached
    }

    func makeUIView(context: Context) -> ObserverView {
        ObserverView(
            onChange: onChange,
            applicationSupportsMultipleScenes: applicationSupportsMultipleScenes
        )
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onChange = onChange
        uiView.notifyCurrentAttachment()
    }

    final class ObserverView: UIView {
        var onChange: (RUMViewTrackingState.Attachment) -> Void
        private var lastAttachment: RUMViewTrackingState.Attachment?
        private let applicationSupportsMultipleScenes: Bool

        init(
            onChange: @escaping (RUMViewTrackingState.Attachment) -> Void,
            applicationSupportsMultipleScenes: Bool = false
        ) {
            self.onChange = onChange
            self.applicationSupportsMultipleScenes = applicationSupportsMultipleScenes
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) {
            self.onChange = { _ in }
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
            notify(window: newWindow)
            super.willMove(toWindow: newWindow)
        }

        func notifyCurrentAttachment() {
            notify(window: window)
        }

        fileprivate func notify(window: UIWindow?) {
            let sceneIdentifier = (window?.windowScene?.session.persistentIdentifier)
                .map { RUMSceneIdentifier(rawValue: $0) }
            let attachment = RUMSceneIdentifierReader.attachment(
                isAttachedToWindow: window != nil,
                sceneIdentifier: sceneIdentifier,
                applicationSupportsMultipleScenes: applicationSupportsMultipleScenes
            )
            guard attachment != lastAttachment else {
                return
            }
            lastAttachment = attachment
            onChange(attachment)
        }
    }
}

/// Reference-backed scene state used by SwiftUI action modifiers.
internal final class RUMSceneTrackingState {
    private(set) var sceneIdentifier: RUMSceneIdentifier?

    func update(attachment: RUMViewTrackingState.Attachment) {
        switch attachment {
        case .detached:
            sceneIdentifier = nil
        case .attached(let sceneIdentifier):
            self.sceneIdentifier = sceneIdentifier
        }
    }
}

internal final class RUMViewTrackingState {
    enum Attachment: Equatable {
        case detached
        case attached(RUMSceneIdentifier?)
    }

    enum Transition: Equatable {
        case start(identity: String, sceneIdentifier: RUMSceneIdentifier?)
        case stop(identity: String, sceneIdentifier: RUMSceneIdentifier?)
    }

    let identity: String
    private(set) var attachment: Attachment = .detached
    private(set) var isAppeared = false
    private(set) var startedSceneIdentifier: RUMSceneIdentifier?
    private var isViewStarted = false

    init(identity: String = UUID().uuidString) {
        self.identity = identity
    }

    func update(attachment: Attachment) -> [Transition] {
        guard self.attachment != attachment else {
            return []
        }
        self.attachment = attachment
        guard isAppeared else {
            return []
        }

        // SwiftUI can transiently detach and reattach representable views while
        // keeping the tracked content visible. Wait for either disappearance or
        // a different destination scene before ending the current RUM view.
        guard case .attached(let sceneIdentifier) = attachment else {
            return []
        }

        if isViewStarted, startedSceneIdentifier == sceneIdentifier {
            return []
        }

        var transitions: [Transition] = []
        if let stop = stopIfNeeded() {
            transitions.append(stop)
        }
        if let start = startIfPossible() {
            transitions.append(start)
        }
        return transitions
    }

    func appear() -> [Transition] {
        isAppeared = true
        return startIfPossible().map { [$0] } ?? []
    }

    func disappear() -> [Transition] {
        isAppeared = false
        return stopIfNeeded().map { [$0] } ?? []
    }

    private func startIfPossible() -> Transition? {
        guard !isViewStarted, case .attached(let sceneIdentifier) = attachment else {
            return nil
        }
        isViewStarted = true
        startedSceneIdentifier = sceneIdentifier
        return .start(identity: identity, sceneIdentifier: sceneIdentifier)
    }

    private func stopIfNeeded() -> Transition? {
        guard isViewStarted else {
            return nil
        }
        isViewStarted = false
        defer { startedSceneIdentifier = nil }
        return .stop(identity: identity, sceneIdentifier: startedSceneIdentifier)
    }
}
#endif

/// `SwiftUI.ViewModifier` which notifes RUM instrumentation when modified view appears and disappears.
/// It makes an entry point to RUM views instrumentation in SwiftUI.
internal struct RUMViewModifier: SwiftUI.ViewModifier {
    /// Datadog RUM instrumentation instance
    let instrumentation: RUMInstrumentation?

    /// View Name used for RUM Explorer.
    let name: String

    /// View Path used for RUM Explorer.
    let path: String

    /// Custom attributes to attach to the View.
    let attributes: [AttributeKey: AttributeValue]

    /// The Content View identifier.
    /// The id will be unique per modified view.
    let identity: String = UUID().uuidString

    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        if instrumentation?.isMultiSceneApplication == true {
            content.modifier(
                RUMMultiSceneViewModifier(
                    instrumentation: instrumentation,
                    name: name,
                    path: path,
                    attributes: attributes
                )
            )
        } else {
            legacyTrackedContent(content)
        }
        #else
        legacyTrackedContent(content)
        #endif
    }

    private func legacyTrackedContent(_ content: Content) -> some View {
        content.onAppear {
            instrumentation?.viewsHandler
                .notify_onAppear(
                    identity: identity,
                    name: name,
                    path: path,
                    attributes: attributes
                )
        }
        .onDisappear {
            instrumentation?.viewsHandler
                .notify_onDisappear(identity: identity)
        }
    }
}

#if os(iOS) || os(visionOS)
private struct RUMMultiSceneViewModifier: SwiftUI.ViewModifier {
    let instrumentation: RUMInstrumentation?
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]

    func body(content: Content) -> some View {
        if #available(iOS 17.0, visionOS 1.0, *) {
            content.modifier(
                RUMTraitBackedMultiSceneViewModifier(
                    instrumentation: instrumentation,
                    name: name,
                    path: path,
                    attributes: attributes
                )
            )
        } else {
            content.modifier(
                RUMAttachmentBackedMultiSceneViewModifier(
                    instrumentation: instrumentation,
                    name: name,
                    path: path,
                    attributes: attributes
                )
            )
        }
    }
}

@available(iOS 17.0, visionOS 1.0, *)
private struct RUMTraitBackedMultiSceneViewModifier: SwiftUI.ViewModifier {
    let instrumentation: RUMInstrumentation?
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    @State private var trackingState = RUMViewTrackingState()
    @State private var didReceiveInitialSceneIdentifier = false

    func body(content: Content) -> some View {
        content
            .background(
                RUMSceneIdentifierReader(applicationSupportsMultipleScenes: true) { attachment in
                    apply(trackingState.update(attachment: attachment))
                }
            )
            .onChange(of: sceneIdentifier, initial: true) { _, sceneIdentifier in
                apply(trackingState.update(attachment: attachment(for: sceneIdentifier)))
                // SwiftUI defines the initial callback as part of this view's
                // appearance. Enqueue once from this supported signal so the
                // scene-aware transition reaches RUM's serial queue as early as
                // possible; relative ordering with outer modifiers is not
                // guaranteed by SwiftUI.
                if !didReceiveInitialSceneIdentifier {
                    didReceiveInitialSceneIdentifier = true
                    apply(trackingState.appear())
                }
            }
            .onAppear {
                apply(trackingState.update(attachment: attachment(for: sceneIdentifier)))
                apply(trackingState.appear())
            }
            .onDisappear {
                apply(trackingState.disappear())
            }
    }

    private func apply(_ transitions: [RUMViewTrackingState.Transition]) {
        transitions.forEach { transition in
            switch transition {
            case .start(let identity, let sceneIdentifier):
                instrumentation?.viewsHandler.notify_onAppear(
                    identity: identity,
                    name: name,
                    path: path,
                    attributes: attributes,
                    sceneIdentifier: sceneIdentifier
                )
            case .stop(let identity, let sceneIdentifier):
                instrumentation?.viewsHandler.notify_onDisappear(
                    identity: identity,
                    sceneIdentifier: sceneIdentifier
                )
            }
        }
    }

    private func attachment(for sceneIdentifier: String?) -> RUMViewTrackingState.Attachment {
        sceneIdentifier
            .map { .attached(RUMSceneIdentifier(rawValue: $0)) }
            ?? .detached
    }
}

private struct RUMAttachmentBackedMultiSceneViewModifier: SwiftUI.ViewModifier {
    let instrumentation: RUMInstrumentation?
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]

    @State private var trackingState = RUMViewTrackingState()

    func body(content: Content) -> some View {
        content
            .background(
                RUMSceneIdentifierReader(applicationSupportsMultipleScenes: true) { attachment in
                    apply(trackingState.update(attachment: attachment))
                }
            )
            .onAppear {
                apply(trackingState.appear())
            }
            .onDisappear {
                apply(trackingState.disappear())
            }
    }

    private func apply(_ transitions: [RUMViewTrackingState.Transition]) {
        transitions.forEach { transition in
            switch transition {
            case .start(let identity, let sceneIdentifier):
                instrumentation?.viewsHandler.notify_onAppear(
                    identity: identity,
                    name: name,
                    path: path,
                    attributes: attributes,
                    sceneIdentifier: sceneIdentifier
                )
            case .stop(let identity, let sceneIdentifier):
                instrumentation?.viewsHandler.notify_onDisappear(
                    identity: identity,
                    sceneIdentifier: sceneIdentifier
                )
            }
        }
    }
}
#endif

public extension SwiftUI.View {
    /// Monitor this view with Datadog RUM. A start and stop events will be logged when this view appears
    /// and disappears.
    ///
    /// - Parameters:
    ///   - name: the View name used for RUM Explorer.
    ///   - attributes: custom attributes to attach to the View.
    ///   - core: The SDK core instance.
    /// - Returns: This view after applying a `ViewModifier` for monitoring the view.
    func trackRUMView(
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        let path = "\(name)/\(typeDescription.hashValue)"
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: name,
                path: path,
                attributes: attributes
            )
        )
    }
}

#endif
