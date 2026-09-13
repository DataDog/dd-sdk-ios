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
/// the public modifier API. When UIKit's scene trait has already bridged into the
/// SwiftUI environment, the reader can report that scene while creating its
/// platform view. The attachment callbacks remain a fail-safe for delayed trait
/// propagation and scene changes.
internal struct RUMSceneIdentifierReader: UIViewRepresentable {
    let applicationSupportsMultipleScenes: Bool
    let initialSceneIdentifier: RUMSceneIdentifier?
    let onCreate: ((ObserverView) -> Void)?
    let onInitialMount: ((RUMSceneIdentifier) -> Void)?
    let onMount: ((RUMSceneIdentifier) -> Void)?
    let onChange: (RUMViewTrackingState.Attachment) -> Void

    init(
        applicationSupportsMultipleScenes: Bool,
        initialSceneIdentifier: RUMSceneIdentifier? = nil,
        onCreate: ((ObserverView) -> Void)? = nil,
        onInitialMount: ((RUMSceneIdentifier) -> Void)? = nil,
        onMount: ((RUMSceneIdentifier) -> Void)? = nil,
        onChange: @escaping (RUMViewTrackingState.Attachment) -> Void
    ) {
        self.applicationSupportsMultipleScenes = applicationSupportsMultipleScenes
        self.initialSceneIdentifier = initialSceneIdentifier
        self.onCreate = onCreate
        self.onInitialMount = onInitialMount
        self.onMount = onMount
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
        if isAttachedToWindow, !applicationSupportsMultipleScenes {
            return .attached(nil)
        }
        return .detached
    }

    func makeUIView(context: Context) -> ObserverView {
        let observer = ObserverView(
            onChange: onChange,
            onMount: onMount,
            applicationSupportsMultipleScenes: applicationSupportsMultipleScenes
        )
        onCreate?(observer)
        if let initialSceneIdentifier {
            onInitialMount?(initialSceneIdentifier)
        }
        return observer
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        update(observer: uiView)
    }

    /// Rebinds a representable reused by SwiftUI. Registration is idempotent,
    /// and the resolved mount callback intentionally runs even when the scene
    /// attachment value is unchanged after a disconnect/reconnect cycle.
    func update(observer: ObserverView) {
        onCreate?(observer)
        observer.onMount = onMount
        observer.onChange = onChange
        observer.notifyCurrentAttachment()
    }

    final class ObserverView: UIView {
        var onChange: (RUMViewTrackingState.Attachment) -> Void
        var onMount: ((RUMSceneIdentifier) -> Void)?
        private var lastAttachment: RUMViewTrackingState.Attachment?
        private var requiresMountNotification = false
        private var lastProvenSceneIdentifier: RUMSceneIdentifier?
        private let applicationSupportsMultipleScenes: Bool

        init(
            onChange: @escaping (RUMViewTrackingState.Attachment) -> Void,
            onMount: ((RUMSceneIdentifier) -> Void)? = nil,
            applicationSupportsMultipleScenes: Bool = false
        ) {
            self.onChange = onChange
            self.onMount = onMount
            self.applicationSupportsMultipleScenes = applicationSupportsMultipleScenes
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) {
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
            notify(window: newWindow)
            super.willMove(toWindow: newWindow)
        }

        func notifyCurrentAttachment() {
            notify(attachment: currentAttachment(for: window))
        }

        fileprivate func notify(window: UIWindow?) {
            notify(attachment: currentAttachment(for: window))
        }

        func notify(attachment: RUMViewTrackingState.Attachment) {
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

        private func currentAttachment(for window: UIWindow?) -> RUMViewTrackingState.Attachment {
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

/// Opaque identity supplied by a future navigation-aware integration to
/// distinguish semantic route occurrences without changing SwiftUI's own view
/// identity. The value remains local control data and is never logged or sent.
internal struct RUMViewOccurrenceKey: Hashable {
    private let value: AnyHashable

    init<Value: Hashable>(_ value: Value) {
        self.value = AnyHashable(value)
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
        case replace(
            oldIdentity: String,
            newIdentity: String,
            sceneIdentifier: RUMSceneIdentifier?
        )
    }

    /// Versioned semantic input for a navigation-aware integration. A caller
    /// must advance `bindingGeneration` whenever it publishes a newer binding
    /// snapshot. This lets the state reject lifecycle callbacks retained by an
    /// older SwiftUI value after the route has changed.
    struct Configuration: Equatable {
        struct Descriptor {
            let name: String
            let path: String
            let attributes: [AttributeKey: AttributeValue]
        }

        let occurrenceKey: RUMViewOccurrenceKey
        let bindingGeneration: UInt64
        let descriptor: Descriptor

        init(
            occurrenceKey: RUMViewOccurrenceKey,
            bindingGeneration: UInt64,
            descriptor: Descriptor
        ) {
            self.occurrenceKey = occurrenceKey
            self.bindingGeneration = bindingGeneration
            self.descriptor = descriptor
        }

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            // The generation identifies the complete binding snapshot,
            // including its descriptor. Descriptor values are Encodable and
            // intentionally have no general equality operation.
            lhs.occurrenceKey == rhs.occurrenceKey
                && lhs.bindingGeneration == rhs.bindingGeneration
        }
    }

    private struct ActiveOccurrence {
        let identity: String
        let configuration: Configuration?
        let lifecycleGeneration: UInt64
        let sceneIdentifier: RUMSceneIdentifier?
    }

    /// Stable lifecycle-command identity retained by the existing modifier.
    /// Keyed integrations allocate a separate identity for each occurrence.
    let identity: String
    private let occurrenceIdentityGenerator: () -> String
    private(set) var attachment: Attachment = .detached
    private(set) var isAppeared = false
    private(set) var configuration: Configuration?
    private(set) var lifecycleGeneration: UInt64 = 0
    private(set) var revision: UInt64 = 0
    private var activeOccurrence: ActiveOccurrence?
    private var lastStartedBindingGeneration: UInt64?
    private var requiresRemount = false
    private var restoresAppearanceOnReaderRemount = false

    init(
        identity: String = UUID().uuidString,
        occurrenceIdentityGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.identity = identity
        self.occurrenceIdentityGenerator = occurrenceIdentityGenerator
    }

    func update(attachment: Attachment) -> [Transition] {
        guard self.attachment != attachment else {
            return []
        }
        return reconcile(
            configuration: nil,
            attachment: attachment,
            isAppeared: nil,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func appear() -> [Transition] {
        reconcile(
            configuration: nil,
            attachment: nil,
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func mount(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        // Creating the hidden platform view is the earliest experimentally
        // reliable signal that explicitly tracked content is mounted in this
        // scene. Treat it as appearance so RUM can enqueue the view before
        // customer lifecycle callbacks. Later callbacks are idempotent.
        reconcile(
            configuration: nil,
            attachment: .attached(sceneIdentifier),
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: true
        )
    }

    /// Handles the platform reader becoming mounted. Unlike a semantic
    /// appearance, routine representable updates must not restart a view that
    /// has already disappeared. Reader mounts are authoritative only for an
    /// initial mount, an active occurrence, or recovery after scene teardown.
    func mountFromReader(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        guard acceptsReaderMount else {
            return []
        }
        return reconcile(
            configuration: nil,
            attachment: .attached(sceneIdentifier),
            isAppeared: appearanceForReaderMount,
            expectedRevision: nil,
            allowsRemount: true
        )
    }

    /// The environment trait can seed the first mount before UIKit attaches
    /// the reader. It is not sufficient evidence for recovery because a
    /// disconnected scene may keep publishing its stale trait value.
    func mountFromInitialTrait(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        guard acceptsInitialTraitMount else {
            return []
        }
        return mount(in: sceneIdentifier)
    }

    func disappear() -> [Transition] {
        reconcile(
            configuration: nil,
            attachment: nil,
            isAppeared: false,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func update(configuration: Configuration, attachment: Attachment) -> [Transition] {
        reconcile(
            configuration: configuration,
            attachment: attachment,
            isAppeared: nil,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func mount(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        reconcile(
            configuration: configuration,
            attachment: .attached(sceneIdentifier),
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: true
        )
    }

    func appear(configuration: Configuration) -> [Transition] {
        reconcile(
            configuration: configuration,
            attachment: nil,
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func disappear(configuration: Configuration) -> [Transition] {
        reconcile(
            configuration: configuration,
            attachment: nil,
            isAppeared: false,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    /// Reconciles the final platform state in one step. Interactive navigation
    /// uses this to commit only the final lifecycle state after UIKit confirms
    /// the transition, instead of replaying speculative SwiftUI callbacks.
    func reconcile(attachment: Attachment?, isAppeared: Bool?) -> [Transition] {
        reconcile(
            configuration: nil,
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: nil,
            allowsRemount: false
        )
    }

    func reconcile(
        configuration: Configuration,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64? = nil,
        allowsRemount: Bool = false
    ) -> [Transition] {
        reconcile(
            configuration: Optional(configuration),
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: expectedRevision,
            allowsRemount: allowsRemount
        )
    }

    func reconcile(
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64,
        allowsRemount: Bool = false
    ) -> [Transition] {
        reconcile(
            configuration: nil,
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: expectedRevision,
            allowsRemount: allowsRemount
        )
    }

    private func reconcile(
        configuration: Configuration?,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64?,
        allowsRemount: Bool
    ) -> [Transition] {
        guard expectedRevision == nil || expectedRevision == revision else {
            return []
        }
        if requiresRemount {
            guard allowsRemount else {
                return []
            }
            if
                let configuration,
                let lastStartedBindingGeneration,
                configuration.bindingGeneration <= lastStartedBindingGeneration {
                return []
            }
        }
        if let configuration {
            guard accepts(configuration) else {
                return []
            }
        } else if self.configuration != nil {
            guard acceptsUnversioned(attachment: attachment, isAppeared: isAppeared) else {
                return []
            }
        }

        let desiredConfiguration = configuration ?? self.configuration
        if
            let activeOccurrence,
            activeOccurrence.configuration != nil,
            case .attached(let sceneIdentifier) = attachment,
            activeOccurrence.sceneIdentifier != sceneIdentifier {
            guard
                let desiredConfiguration,
                desiredConfiguration.bindingGeneration
                    > (activeOccurrence.configuration?.bindingGeneration ?? 0)
            else {
                return []
            }
        }

        var didMutate = false
        if requiresRemount {
            requiresRemount = false
            restoresAppearanceOnReaderRemount = false
            didMutate = true
        }
        if let configuration, self.configuration != configuration {
            self.configuration = configuration
            didMutate = true
        }
        if let attachment {
            if self.attachment != attachment {
                self.attachment = attachment
                didMutate = true
            }
        }
        if let isAppeared {
            if self.isAppeared != isAppeared {
                self.isAppeared = isAppeared
                didMutate = true
            }
        }

        guard self.isAppeared else {
            let transitions = stopIfNeeded().map { [$0] } ?? []
            finishMutation(didMutate || !transitions.isEmpty)
            return transitions
        }

        // SwiftUI can transiently detach and reattach representable views while
        // keeping the tracked content visible. Wait for either disappearance or
        // a different destination scene before ending the current RUM view. A
        // semantic-key change is not transient: stop the old occurrence using
        // its last proven scene and wait for the new attachment.
        guard case .attached(let sceneIdentifier) = self.attachment else {
            let keyChanged = activeOccurrence?.configuration?.occurrenceKey
                != self.configuration?.occurrenceKey
            let transitions = keyChanged ? stopIfNeeded().map { [$0] } ?? [] : []
            finishMutation(didMutate || !transitions.isEmpty)
            return transitions
        }

        guard let activeOccurrence else {
            let transitions = start(in: sceneIdentifier).map { [$0] } ?? []
            finishMutation(didMutate || !transitions.isEmpty)
            return transitions
        }

        if activeOccurrence.sceneIdentifier != sceneIdentifier {
            var transitions: [Transition] = []
            if let stop = stopIfNeeded() {
                transitions.append(stop)
            }
            if let start = start(in: sceneIdentifier) {
                transitions.append(start)
            }
            finishMutation(true)
            return transitions
        }

        if activeOccurrence.configuration?.occurrenceKey != self.configuration?.occurrenceKey {
            guard let newOccurrence = makeOccurrence(in: sceneIdentifier) else {
                finishMutation(didMutate)
                return []
            }
            self.activeOccurrence = newOccurrence
            finishMutation(true)
            return [
                .replace(
                    oldIdentity: activeOccurrence.identity,
                    newIdentity: newOccurrence.identity,
                    sceneIdentifier: sceneIdentifier
                )
            ]
        }

        finishMutation(didMutate)
        return []
    }

    var sceneIdentifier: RUMSceneIdentifier? {
        if case .attached(let sceneIdentifier) = attachment {
            return sceneIdentifier
        }
        return activeOccurrence?.sceneIdentifier
    }

    var activeLifecycleGeneration: UInt64? {
        activeOccurrence?.lifecycleGeneration
    }

    var acceptsReaderMount: Bool {
        lifecycleGeneration == 0 || activeOccurrence != nil || requiresRemount
    }

    var acceptsInitialTraitMount: Bool {
        lifecycleGeneration == 0 && !requiresRemount && activeOccurrence == nil
    }

    var needsReaderRemount: Bool {
        requiresRemount
    }

    var appearanceForReaderMount: Bool? {
        if requiresRemount {
            return restoresAppearanceOnReaderRemount ? true : nil
        }
        return acceptsReaderMount ? true : nil
    }

    func descriptor(for identity: String) -> Configuration.Descriptor? {
        guard activeOccurrence?.identity == identity else {
            return nil
        }
        return activeOccurrence?.configuration?.descriptor
    }

    /// Mirrors handler teardown after a scene disconnect without emitting a
    /// second stop. The state retains its keyed generation fence so callbacks
    /// from the disconnected reader cannot recreate the removed handler entry.
    /// A later platform mount is the only signal allowed to create a new
    /// occurrence.
    @discardableResult
    func invalidateAfterSceneDisconnect(
        _ sceneIdentifier: RUMSceneIdentifier,
        forceForPending: Bool = false
    ) -> Bool {
        if
            requiresRemount,
            activeOccurrence == nil,
            attachment == .detached,
            !isAppeared {
            return false
        }

        let committedSceneIdentifier: RUMSceneIdentifier?
        if let activeOccurrence {
            committedSceneIdentifier = activeOccurrence.sceneIdentifier
        } else if case .attached(let attachedSceneIdentifier) = attachment {
            committedSceneIdentifier = attachedSceneIdentifier
        } else {
            committedSceneIdentifier = nil
        }
        guard
            committedSceneIdentifier == sceneIdentifier
                || (committedSceneIdentifier == nil && forceForPending)
        else {
            return false
        }

        restoresAppearanceOnReaderRemount = isAppeared
        attachment = .detached
        isAppeared = false
        activeOccurrence = nil
        requiresRemount = true
        finishMutation(true)
        return true
    }

    private func accepts(_ configuration: Configuration) -> Bool {
        guard let current = self.configuration else {
            return true
        }
        guard configuration.bindingGeneration >= current.bindingGeneration else {
            return false
        }
        if configuration.bindingGeneration == current.bindingGeneration {
            return configuration.occurrenceKey == current.occurrenceKey
        }
        return true
    }

    func acceptsUnversioned(attachment: Attachment?, isAppeared: Bool?) -> Bool {
        guard configuration != nil else {
            return true
        }
        guard isAppeared == nil else {
            return false
        }
        guard let attachment else {
            return true
        }
        switch attachment {
        case .detached:
            return true
        case .attached(let sceneIdentifier):
            guard let activeOccurrence else {
                return !self.isAppeared
            }
            return activeOccurrence.sceneIdentifier == sceneIdentifier
        }
    }

    private func start(in sceneIdentifier: RUMSceneIdentifier?) -> Transition? {
        guard activeOccurrence == nil else {
            return nil
        }
        guard let occurrence = makeOccurrence(in: sceneIdentifier) else {
            return nil
        }
        activeOccurrence = occurrence
        return .start(identity: occurrence.identity, sceneIdentifier: sceneIdentifier)
    }

    private func stopIfNeeded() -> Transition? {
        guard let occurrence = activeOccurrence else {
            return nil
        }
        activeOccurrence = nil
        return .stop(
            identity: occurrence.identity,
            sceneIdentifier: occurrence.sceneIdentifier
        )
    }

    private func makeOccurrence(in sceneIdentifier: RUMSceneIdentifier?) -> ActiveOccurrence? {
        if let configuration {
            guard
                lastStartedBindingGeneration == nil
                    || configuration.bindingGeneration > (lastStartedBindingGeneration ?? 0)
            else {
                return nil
            }
            lastStartedBindingGeneration = configuration.bindingGeneration
        }
        lifecycleGeneration &+= 1
        return ActiveOccurrence(
            identity: configuration == nil ? identity : occurrenceIdentityGenerator(),
            configuration: configuration,
            lifecycleGeneration: lifecycleGeneration,
            sceneIdentifier: sceneIdentifier
        )
    }

    private func finishMutation(_ didMutate: Bool) {
        if didMutate {
            revision &+= 1
        }
    }
}

/// Applies reconciled SwiftUI lifecycle transitions to the scene-aware view
/// handler. Keyed occurrences own an immutable descriptor snapshot; legacy
/// transitions use the modifier's existing descriptor for compatibility.
internal enum RUMSwiftUIViewTransitionPublisher {
    static func publish(
        _ transitions: [RUMViewTrackingState.Transition],
        state: RUMViewTrackingState,
        fallback: RUMViewTrackingState.Configuration.Descriptor,
        to viewsHandler: RUMViewsHandler?
    ) {
        transitions.forEach { transition in
            switch transition {
            case .start(let identity, let sceneIdentifier):
                let descriptor = state.descriptor(for: identity) ?? fallback
                viewsHandler?.notify_onAppear(
                    identity: identity,
                    name: descriptor.name,
                    path: descriptor.path,
                    attributes: descriptor.attributes,
                    sceneIdentifier: sceneIdentifier
                )
            case .stop(let identity, let sceneIdentifier):
                viewsHandler?.notify_onDisappear(
                    identity: identity,
                    sceneIdentifier: sceneIdentifier
                )
            case .replace(let oldIdentity, let newIdentity, let sceneIdentifier):
                let descriptor = state.descriptor(for: newIdentity) ?? fallback
                viewsHandler?.notify_replaceOccurrence(
                    oldIdentity: oldIdentity,
                    newIdentity: newIdentity,
                    name: descriptor.name,
                    path: descriptor.path,
                    attributes: descriptor.attributes,
                    sceneIdentifier: sceneIdentifier
                )
            }
        }
    }
}

#if os(iOS)
internal protocol RUMSwiftUITransitionCoordinating: AnyObject {
    var identity: ObjectIdentifier { get }
    var initiallyInteractive: Bool { get }

    func registerCompletion(_ completion: @escaping (_ isCancelled: Bool) -> Void) -> Bool
}

private final class RUMUIKitSwiftUITransitionCoordinator: RUMSwiftUITransitionCoordinating {
    private let coordinator: any UIViewControllerTransitionCoordinator

    var identity: ObjectIdentifier {
        ObjectIdentifier(coordinator as AnyObject)
    }

    var initiallyInteractive: Bool {
        coordinator.initiallyInteractive
    }

    init(coordinator: any UIViewControllerTransitionCoordinator) {
        self.coordinator = coordinator
    }

    func registerCompletion(_ completion: @escaping (_ isCancelled: Bool) -> Void) -> Bool {
        coordinator.animate(alongsideTransition: nil) { context in
            completion(context.isCancelled)
        }
    }
}

/// Finds the interactive UIKit transition associated with one explicitly
/// tracked SwiftUI view. An attached reader is the strongest signal because it
/// identifies that view's hosting controller. A scene-root lookup is only used
/// while a newly created reader has not joined the responder hierarchy yet.
///
/// The fallback is intentionally scoped to the matching `UIWindowScene`: a
/// transition in another window must never delay this view's lifecycle.
internal struct RUMSwiftUITransitionCoordinatorProvider {
    typealias SceneViewControllers = (RUMSceneIdentifier) -> [UIViewController]
    typealias ControllerCoordinator = (UIViewController) -> (any RUMSwiftUITransitionCoordinating)?

    private let sceneViewControllers: SceneViewControllers
    private let controllerCoordinator: ControllerCoordinator

    init() {
        sceneViewControllers = { sceneIdentifier in
            guard let application = UIApplication.dd.managedShared else {
                return []
            }
            guard let scene = application.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.persistentIdentifier == sceneIdentifier.rawValue })
            else {
                return []
            }
            return scene.windows.compactMap(\.rootViewController)
        }
        controllerCoordinator = { viewController in
            guard let coordinator = viewController.transitionCoordinator else {
                return nil
            }
            return RUMUIKitSwiftUITransitionCoordinator(coordinator: coordinator)
        }
    }

    init(
        sceneViewControllers: @escaping SceneViewControllers,
        controllerCoordinator: @escaping ControllerCoordinator
    ) {
        self.sceneViewControllers = sceneViewControllers
        self.controllerCoordinator = controllerCoordinator
    }

    func coordinator(
        for sceneIdentifier: RUMSceneIdentifier,
        observers: [RUMSceneIdentifierReader.ObserverView]
    ) -> (any RUMSwiftUITransitionCoordinating)? {
        let attachedViewControllers = observers.compactMap { observer -> UIViewController? in
            guard observer.currentSceneIdentifier == sceneIdentifier else {
                return nil
            }
            return observer.nearestViewController
        }
        if !attachedViewControllers.isEmpty {
            return firstInteractiveCoordinator(in: attachedViewControllers, includesAncestors: true)
        }
        if observers.contains(where: { $0.nearestViewController != nil }) {
            return nil
        }

        return firstInteractiveCoordinator(
            in: sceneViewControllers(sceneIdentifier),
            includesAncestors: false
        )
    }

    private func firstInteractiveCoordinator(
        in roots: [UIViewController],
        includesAncestors: Bool
    ) -> (any RUMSwiftUITransitionCoordinating)? {
        var candidates = roots
        if includesAncestors {
            candidates.append(contentsOf: roots.flatMap { ancestorViewControllers(of: $0) })
        } else {
            candidates = roots.flatMap { viewControllerHierarchy(from: $0) }
        }

        var visited: Set<ObjectIdentifier> = []
        for candidate in candidates where visited.insert(ObjectIdentifier(candidate)).inserted {
            guard
                let coordinator = controllerCoordinator(candidate),
                coordinator.initiallyInteractive
            else {
                continue
            }
            return coordinator
        }
        return nil
    }

    private func ancestorViewControllers(of viewController: UIViewController) -> [UIViewController] {
        var ancestors: [UIViewController] = []
        var parent = viewController.parent
        while let current = parent {
            ancestors.append(current)
            parent = current.parent
        }
        return ancestors
    }

    private func viewControllerHierarchy(from root: UIViewController) -> [UIViewController] {
        var hierarchy: [UIViewController] = []
        var pending = [root]
        var visited: Set<ObjectIdentifier> = []
        while let current = pending.popLast() {
            guard visited.insert(ObjectIdentifier(current)).inserted else {
                continue
            }
            hierarchy.append(current)
            pending.append(contentsOf: current.children)
            if let presented = current.presentedViewController {
                pending.append(presented)
            }
        }
        return hierarchy
    }
}

/// Delays explicit SwiftUI view lifecycle changes while UIKit is resolving an
/// interactive navigation transition. SwiftUI reports the destination's
/// appearance speculatively; UIKit's coordinator is the commit signal that
/// distinguishes a completed navigation from a cancelled gesture.
internal final class RUMSwiftUIInteractiveTransitionArbiter {
    private struct TransitionKey: Hashable {
        let sceneIdentifier: RUMSceneIdentifier
        let coordinatorIdentity: ObjectIdentifier
    }

    enum Intent {
        case update(RUMViewTrackingState.Attachment)
        case initialMount(RUMSceneIdentifier)
        case mount(RUMSceneIdentifier)
        case appear
        case disappear
        case reconcile(
            configuration: RUMViewTrackingState.Configuration,
            attachment: RUMViewTrackingState.Attachment?,
            isAppeared: Bool?
        )

        fileprivate var configuration: RUMViewTrackingState.Configuration? {
            switch self {
            case .reconcile(let configuration, _, _):
                return configuration
            case .update, .initialMount, .mount, .appear, .disappear:
                return nil
            }
        }

        fileprivate var attachment: RUMViewTrackingState.Attachment? {
            switch self {
            case .update(let attachment):
                return attachment
            case .mount(let sceneIdentifier):
                return .attached(sceneIdentifier)
            case .initialMount(let sceneIdentifier):
                return .attached(sceneIdentifier)
            case .appear, .disappear:
                return nil
            case .reconcile(_, let attachment, _):
                return attachment
            }
        }

        fileprivate var isAppeared: Bool? {
            switch self {
            case .initialMount, .mount, .appear:
                return true
            case .disappear:
                return false
            case .update:
                return nil
            case .reconcile(_, _, let isAppeared):
                return isAppeared
            }
        }

        fileprivate var sceneIdentifier: RUMSceneIdentifier? {
            switch self {
            case .initialMount(let sceneIdentifier), .mount(let sceneIdentifier):
                return sceneIdentifier
            case .update(.attached(let sceneIdentifier)):
                return sceneIdentifier
            case .update(.detached), .appear, .disappear:
                return nil
            case .reconcile(_, .attached(let sceneIdentifier), _):
                return sceneIdentifier
            case .reconcile(_, .detached, _), .reconcile(_, nil, _):
                return nil
            }
        }

        fileprivate func apply(to state: RUMViewTrackingState) -> [RUMViewTrackingState.Transition] {
            switch self {
            case .update(let attachment):
                return state.update(attachment: attachment)
            case .initialMount(let sceneIdentifier):
                return state.mountFromInitialTrait(in: sceneIdentifier)
            case .mount(let sceneIdentifier):
                return state.mountFromReader(in: sceneIdentifier)
            case .appear:
                return state.appear()
            case .disappear:
                return state.disappear()
            case .reconcile(let configuration, let attachment, let isAppeared):
                return state.reconcile(
                    configuration: configuration,
                    attachment: attachment,
                    isAppeared: isAppeared
                )
            }
        }
    }

    typealias CoordinatorProvider = (
        _ sceneIdentifier: RUMSceneIdentifier,
        _ observers: [RUMSceneIdentifierReader.ObserverView]
    ) -> (any RUMSwiftUITransitionCoordinating)?

    private final class ObserverRegistration {
        weak var observer: RUMSceneIdentifierReader.ObserverView?
        weak var state: RUMViewTrackingState?

        init(observer: RUMSceneIdentifierReader.ObserverView, state: RUMViewTrackingState) {
            self.observer = observer
            self.state = state
        }
    }

    private final class DeferredState {
        let state: RUMViewTrackingState
        let sequence: Int
        var baseRevision: UInt64
        let baseIsAppeared: Bool
        var send: ([RUMViewTrackingState.Transition]) -> Void
        var isProvisional: Bool
        var configuration: RUMViewTrackingState.Configuration?
        var attachment: RUMViewTrackingState.Attachment?
        var isAppeared: Bool?
        var allowsRemount = false
        var containsReaderMount = false

        init(
            state: RUMViewTrackingState,
            sequence: Int,
            isProvisional: Bool,
            send: @escaping ([RUMViewTrackingState.Transition]) -> Void
        ) {
            self.state = state
            self.sequence = sequence
            self.baseRevision = state.revision
            self.baseIsAppeared = state.isAppeared
            self.isProvisional = isProvisional
            self.configuration = state.configuration
            self.send = send
        }

        func merge(
            _ intent: Intent,
            send: @escaping ([RUMViewTrackingState.Transition]) -> Void
        ) -> Bool {
            guard accepts(intent) else {
                return false
            }
            if let incomingConfiguration = intent.configuration {
                self.configuration = incomingConfiguration
                self.send = send
            } else if configuration == nil {
                // Legacy modifiers have no versioned binding. Preserve their
                // existing behavior while using the newest callback closure.
                self.send = send
            }
            if case .initialMount(let sceneIdentifier) = intent {
                attachment = .attached(sceneIdentifier)
                isAppeared = true
            } else if case .mount(let sceneIdentifier) = intent {
                attachment = .attached(sceneIdentifier)
                isAppeared = state.appearanceForReaderMount
                allowsRemount = true
                containsReaderMount = true
            } else {
                if let attachment = intent.attachment {
                    self.attachment = attachment
                }
                if let isAppeared = intent.isAppeared {
                    self.isAppeared = isAppeared
                }
            }
            return true
        }

        func accepts(_ intent: Intent) -> Bool {
            if case .initialMount = intent, !state.acceptsInitialTraitMount {
                return false
            }
            if case .mount = intent, !state.acceptsReaderMount {
                return false
            }
            guard let incomingConfiguration = intent.configuration else {
                return state.acceptsUnversioned(
                    attachment: intent.attachment,
                    isAppeared: intent.isAppeared
                )
            }
            guard let configuration else {
                return true
            }
            if incomingConfiguration.bindingGeneration < configuration.bindingGeneration {
                return false
            }
            if incomingConfiguration.bindingGeneration == configuration.bindingGeneration {
                return incomingConfiguration.occurrenceKey == configuration.occurrenceKey
            }
            return true
        }

        func rebaseAfterSceneDisconnect() {
            baseRevision = state.revision
            isAppeared = isAppeared ?? baseIsAppeared
            allowsRemount = true
        }

        var needsReaderRemountRearm: Bool {
            containsReaderMount && state.needsReaderRemount
        }

        func commit() {
            let transitions: [RUMViewTrackingState.Transition]
            if let configuration {
                transitions = state.reconcile(
                    configuration: configuration,
                    attachment: attachment,
                    isAppeared: isAppeared,
                    expectedRevision: baseRevision,
                    allowsRemount: allowsRemount
                )
            } else {
                transitions = state.reconcile(
                    attachment: attachment,
                    isAppeared: isAppeared,
                    expectedRevision: baseRevision,
                    allowsRemount: allowsRemount
                )
            }
            send(transitions)
        }
    }

    private final class DeferredTransition {
        private(set) var states: [ObjectIdentifier: DeferredState] = [:]
        private var nextSequence = 0

        func contains(state: RUMViewTrackingState) -> Bool {
            states[ObjectIdentifier(state)] != nil
        }

        func merge(
            _ intent: Intent,
            state: RUMViewTrackingState,
            isProvisional: Bool,
            send: @escaping ([RUMViewTrackingState.Transition]) -> Void
        ) {
            let identity = ObjectIdentifier(state)
            if let existing = states[identity] {
                guard existing.merge(intent, send: send) else {
                    return
                }
                if !isProvisional {
                    existing.isProvisional = false
                }
            } else {
                let deferredState = DeferredState(
                    state: state,
                    sequence: nextSequence,
                    isProvisional: isProvisional,
                    send: send
                )
                guard deferredState.merge(intent, send: send) else {
                    return
                }
                nextSequence += 1
                states[identity] = deferredState
            }
        }

        func deferredState(for state: RUMViewTrackingState) -> DeferredState? {
            states[ObjectIdentifier(state)]
        }

        func remove(state: RUMViewTrackingState) -> DeferredState? {
            states.removeValue(forKey: ObjectIdentifier(state))
        }

        var trackingStates: [RUMViewTrackingState] {
            states.values.map(\.state)
        }

        func rebaseAfterSceneDisconnect(statesWithIdentities identities: Set<ObjectIdentifier>) {
            states.forEach { identity, state in
                if identities.contains(identity) {
                    state.rebaseAfterSceneDisconnect()
                }
            }
        }

        var statesNeedingReaderRemountRearm: [RUMViewTrackingState] {
            states.values.compactMap { state in
                state.needsReaderRemountRearm ? state.state : nil
            }
        }

        func remove(statesWithIdentities identities: Set<ObjectIdentifier>) {
            states = states.filter { identity, _ in
                !identities.contains(identity)
            }
        }

        var isEmpty: Bool {
            states.isEmpty
        }

        func commit() {
            let orderedStates = states.values.sorted { lhs, rhs in
                if lhs.isAppeared == rhs.isAppeared {
                    return lhs.sequence < rhs.sequence
                }
                if lhs.isAppeared == false {
                    return true
                }
                if rhs.isAppeared == false {
                    return false
                }
                return lhs.sequence < rhs.sequence
            }
            orderedStates.forEach { $0.commit() }
        }
    }

    private let notificationCenter: NotificationCenter
    private let coordinatorProvider: CoordinatorProvider
    private var disconnectObserver: NSObjectProtocol?
    private var observerRegistrations: [ObjectIdentifier: ObserverRegistration] = [:]
    private var deferredTransitions: [TransitionKey: DeferredTransition] = [:]

    convenience init(notificationCenter: NotificationCenter) {
        let provider = RUMSwiftUITransitionCoordinatorProvider()
        self.init(notificationCenter: notificationCenter) { sceneIdentifier, observers in
            provider.coordinator(for: sceneIdentifier, observers: observers)
        }
    }

    init(notificationCenter: NotificationCenter, coordinatorProvider: @escaping CoordinatorProvider) {
        self.notificationCenter = notificationCenter
        self.coordinatorProvider = coordinatorProvider
        disconnectObserver = notificationCenter.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene else {
                return
            }
            self?.discard(sceneIdentifier: RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier))
        }
    }

    deinit {
        if let disconnectObserver {
            notificationCenter.removeObserver(disconnectObserver)
        }
    }

    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        for state: RUMViewTrackingState
    ) {
        guard Thread.isMainThread else {
            return
        }
        observerRegistrations[ObjectIdentifier(observer)] = ObserverRegistration(
            observer: observer,
            state: state
        )
    }

    func process(
        _ intent: Intent,
        state: RUMViewTrackingState,
        send: @escaping ([RUMViewTrackingState.Transition]) -> Void
    ) {
        guard Thread.isMainThread else {
            send(intent.apply(to: state))
            return
        }

        if let pending = deferredTransition(for: state) {
            if let destinationSceneIdentifier = intent.sceneIdentifier,
               destinationSceneIdentifier != pending.key.sceneIdentifier {
                commitOutsidePendingTransition(
                    intent,
                    state: state,
                    pending: pending,
                    send: send
                )
                return
            }

            let isProvisional = pending.transition
                .deferredState(for: state)?
                .isProvisional == true
            var remainsProvisional = false
            if isProvisional {
                let observers = liveObservers(
                    for: state,
                    sceneIdentifier: pending.key.sceneIdentifier
                )
                let hasAttachedObserver = observers.contains { $0.nearestViewController != nil }
                remainsProvisional = !hasAttachedObserver
                if hasAttachedObserver {
                    let coordinator = coordinatorProvider(pending.key.sceneIdentifier, observers)
                    if coordinator?.identity != pending.key.coordinatorIdentity {
                        commitOutsidePendingTransition(
                            intent,
                            state: state,
                            pending: pending,
                            send: send
                        )
                        return
                    }
                }
            }

            pending.transition.merge(
                intent,
                state: state,
                isProvisional: remainsProvisional,
                send: send
            )
            return
        }

        guard let sceneIdentifier = intent.sceneIdentifier ?? state.sceneIdentifier
        else {
            send(intent.apply(to: state))
            return
        }

        let observers = liveObservers(for: state, sceneIdentifier: sceneIdentifier)
        let isProvisional = observers.allSatisfy { $0.nearestViewController == nil }
        guard
            let coordinator = coordinatorProvider(sceneIdentifier, observers),
            coordinator.initiallyInteractive
        else {
            send(intent.apply(to: state))
            return
        }

        let transitionKey = TransitionKey(
            sceneIdentifier: sceneIdentifier,
            coordinatorIdentity: coordinator.identity
        )
        if let deferredTransition = deferredTransitions[transitionKey] {
            deferredTransition.merge(
                intent,
                state: state,
                isProvisional: isProvisional,
                send: send
            )
            return
        }

        let deferredTransition = DeferredTransition()
        deferredTransition.merge(
            intent,
            state: state,
            isProvisional: isProvisional,
            send: send
        )
        guard !deferredTransition.isEmpty else {
            return
        }
        deferredTransitions[transitionKey] = deferredTransition

        let didRegister = coordinator.registerCompletion { [weak self] isCancelled in
            let resolve = {
                self?.resolve(
                    transitionKey: transitionKey,
                    expectedTransition: deferredTransition,
                    isCancelled: isCancelled
                )
            }
            if Thread.isMainThread {
                resolve()
            } else {
                DispatchQueue.main.async {
                    resolve()
                }
            }
        }

        guard !didRegister else {
            return
        }
        guard deferredTransitions[transitionKey] === deferredTransition else {
            return
        }
        deferredTransitions.removeValue(forKey: transitionKey)
        deferredTransition.commit()
    }

    func discard(sceneIdentifier: RUMSceneIdentifier) {
        guard Thread.isMainThread else {
            return
        }

        var candidateStates: [ObjectIdentifier: RUMViewTrackingState] = [:]
        observerRegistrations.values.forEach { registration in
            guard let state = registration.state else {
                return
            }
            candidateStates[ObjectIdentifier(state)] = state
        }
        var statesPendingInDisconnectedScene: Set<ObjectIdentifier> = []
        deferredTransitions.forEach { key, transition in
            transition.trackingStates.forEach { state in
                let identity = ObjectIdentifier(state)
                candidateStates[identity] = state
                if key.sceneIdentifier == sceneIdentifier {
                    statesPendingInDisconnectedScene.insert(identity)
                }
            }
        }

        var invalidatedStateIdentities: Set<ObjectIdentifier> = []
        candidateStates.forEach { identity, state in
            let didInvalidate = state.invalidateAfterSceneDisconnect(
                sceneIdentifier,
                forceForPending: statesPendingInDisconnectedScene.contains(identity)
            )
            if didInvalidate {
                invalidatedStateIdentities.insert(identity)
            }
        }

        var disconnectedObserverIdentities: Set<ObjectIdentifier> = []
        observerRegistrations.forEach { observerIdentity, registration in
            guard
                let observer = registration.observer,
                observer.lastSceneIdentifier == sceneIdentifier
            else {
                return
            }
            observer.markSceneDisconnected(sceneIdentifier)
            disconnectedObserverIdentities.insert(observerIdentity)
        }
        observerRegistrations.values.forEach { registration in
            guard
                let observer = registration.observer,
                let state = registration.state,
                invalidatedStateIdentities.contains(ObjectIdentifier(state))
            else {
                return
            }
            observer.markSceneDisconnected(sceneIdentifier)
        }

        deferredTransitions = deferredTransitions.filter { key, transition in
            guard key.sceneIdentifier != sceneIdentifier else {
                return false
            }
            transition.rebaseAfterSceneDisconnect(
                statesWithIdentities: invalidatedStateIdentities
            )
            return !transition.isEmpty
        }
        observerRegistrations = observerRegistrations.filter { _, registration in
            guard let observer = registration.observer, registration.state != nil else {
                return false
            }
            return !disconnectedObserverIdentities.contains(ObjectIdentifier(observer))
        }
    }

    private func resolve(
        transitionKey: TransitionKey,
        expectedTransition: DeferredTransition,
        isCancelled: Bool
    ) {
        guard
            let deferredTransition = deferredTransitions[transitionKey],
            deferredTransition === expectedTransition
        else {
            return
        }
        deferredTransitions.removeValue(forKey: transitionKey)
        if isCancelled {
            rearmReaderMounts(
                for: deferredTransition.statesNeedingReaderRemountRearm,
                sceneIdentifier: transitionKey.sceneIdentifier
            )
        } else {
            deferredTransition.commit()
        }
    }

    private func liveObservers(
        for state: RUMViewTrackingState,
        sceneIdentifier: RUMSceneIdentifier
    ) -> [RUMSceneIdentifierReader.ObserverView] {
        observerRegistrations = observerRegistrations.filter { _, registration in
            registration.observer != nil && registration.state != nil
        }
        return observerRegistrations.values.compactMap { registration in
            guard
                registration.state === state,
                let observer = registration.observer,
                observer.lastSceneIdentifier == nil
                    || observer.lastSceneIdentifier == sceneIdentifier
            else {
                return nil
            }
            return observer
        }
    }

    private func rearmReaderMounts(
        for states: [RUMViewTrackingState],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        let identities = Set(states.map(ObjectIdentifier.init))
        observerRegistrations.values.forEach { registration in
            guard
                let observer = registration.observer,
                let state = registration.state,
                identities.contains(ObjectIdentifier(state))
            else {
                return
            }
            observer.markSceneDisconnected(sceneIdentifier)
        }
    }

    private func deferredTransition(
        for state: RUMViewTrackingState
    ) -> (key: TransitionKey, transition: DeferredTransition)? {
        let match = deferredTransitions.first { _, transition in
            transition.contains(state: state)
        }
        return match.map { (key: $0.key, transition: $0.value) }
    }

    private func commitOutsidePendingTransition(
        _ intent: Intent,
        state: RUMViewTrackingState,
        pending: (key: TransitionKey, transition: DeferredTransition),
        send: @escaping ([RUMViewTrackingState.Transition]) -> Void
    ) {
        guard
            let deferredState = pending.transition.deferredState(for: state),
            deferredState.accepts(intent)
        else {
            return
        }
        guard pending.transition.remove(state: state) != nil else {
            return
        }
        if pending.transition.isEmpty {
            deferredTransitions.removeValue(forKey: pending.key)
        }
        guard deferredState.merge(intent, send: send) else {
            return
        }
        deferredState.commit()
    }
}
#endif
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
                    attributes: attributes,
                    startsOnInitialMount: startsOnInitialMount
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

    private var startsOnInitialMount: Bool {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }
}

@available(iOS 17.0, visionOS 1.0, *)
private struct RUMTraitBackedMultiSceneViewModifier: SwiftUI.ViewModifier {
    let instrumentation: RUMInstrumentation?
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let startsOnInitialMount: Bool

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    @State private var trackingState = RUMViewTrackingState()
    @State private var didReceiveInitialSceneIdentifier = false

    func body(content: Content) -> some View {
        content
            .background(
                RUMSceneIdentifierReader(
                    applicationSupportsMultipleScenes: true,
                    initialSceneIdentifier: initialSceneIdentifier,
                    onCreate: { observer in
                        register(observer: observer)
                    },
                    onInitialMount: startsOnInitialMount ? { sceneIdentifier in
                        initialMount(in: sceneIdentifier)
                    } : nil,
                    onMount: startsOnInitialMount ? { sceneIdentifier in
                        mount(in: sceneIdentifier)
                    } : nil,
                    onChange: { attachment in
                        update(attachment: attachment)
                    }
                )
            )
            .onChange(of: sceneIdentifier, initial: true) { _, sceneIdentifier in
                update(attachment: attachment(for: sceneIdentifier))
                // SwiftUI defines the initial callback as part of this view's
                // appearance. Enqueue once from this supported signal so the
                // scene-aware transition reaches RUM's serial queue as early as
                // possible; relative ordering with outer modifiers is not
                // guaranteed by SwiftUI.
                if !didReceiveInitialSceneIdentifier {
                    didReceiveInitialSceneIdentifier = true
                    appear()
                }
            }
            .onAppear {
                update(attachment: attachment(for: sceneIdentifier))
                appear()
            }
            .onDisappear {
                disappear()
            }
    }

    private var initialSceneIdentifier: RUMSceneIdentifier? {
        guard startsOnInitialMount else {
            return nil
        }
        return sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    private func register(observer: RUMSceneIdentifierReader.ObserverView) {
        #if os(iOS)
        transitionArbiter?.register(observer: observer, for: trackingState)
        #endif
    }

    private func mount(in sceneIdentifier: RUMSceneIdentifier) {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.mount(sceneIdentifier), state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.mountFromReader(in: sceneIdentifier))
    }

    private func initialMount(in sceneIdentifier: RUMSceneIdentifier) {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(
                .initialMount(sceneIdentifier),
                state: trackingState,
                send: apply
            )
            return
        }
        #endif
        apply(trackingState.mountFromInitialTrait(in: sceneIdentifier))
    }

    private func update(attachment: RUMViewTrackingState.Attachment) {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.update(attachment), state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.update(attachment: attachment))
    }

    private func appear() {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.appear, state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.appear())
    }

    private func disappear() {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.disappear, state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.disappear())
    }

    #if os(iOS)
    private var transitionArbiter: RUMSwiftUIInteractiveTransitionArbiter? {
        guard startsOnInitialMount else {
            return nil
        }
        return instrumentation?.swiftUIInteractiveTransitionArbiter
    }
    #endif

    private func apply(_ transitions: [RUMViewTrackingState.Transition]) {
        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: trackingState,
            fallback: .init(name: name, path: path, attributes: attributes),
            to: instrumentation?.viewsHandler
        )
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
        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: trackingState,
            fallback: .init(name: name, path: path, attributes: attributes),
            to: instrumentation?.viewsHandler
        )
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
