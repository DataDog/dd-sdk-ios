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
