/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI)
import Combine
import SwiftUI
import DatadogInternal
#if compiler(>=6.4)
import Observation
#endif

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
    let onReconcile: ((RUMViewTrackingState.Attachment) -> Void)?
    let onChange: (RUMViewTrackingState.Attachment) -> Void

    init(
        applicationSupportsMultipleScenes: Bool,
        initialSceneIdentifier: RUMSceneIdentifier? = nil,
        onCreate: ((ObserverView) -> Void)? = nil,
        onInitialMount: ((RUMSceneIdentifier) -> Void)? = nil,
        onMount: ((RUMSceneIdentifier) -> Void)? = nil,
        onReconcile: ((RUMViewTrackingState.Attachment) -> Void)? = nil,
        onChange: @escaping (RUMViewTrackingState.Attachment) -> Void
    ) {
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
        onReconcile?(observer.currentAttachment)
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

        var currentAttachment: RUMViewTrackingState.Attachment {
            currentAttachment(for: window)
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
        let isCurrentDestination: Bool

        init(
            occurrenceKey: RUMViewOccurrenceKey,
            bindingGeneration: UInt64,
            descriptor: Descriptor,
            isCurrentDestination: Bool = true
        ) {
            self.occurrenceKey = occurrenceKey
            self.bindingGeneration = bindingGeneration
            self.descriptor = descriptor
            self.isCurrentDestination = isCurrentDestination
        }

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            // The generation identifies the descriptor's binding snapshot.
            // Descriptor values are Encodable and intentionally have no
            // general equality operation.
            lhs.occurrenceKey == rhs.occurrenceKey
                && lhs.bindingGeneration == rhs.bindingGeneration
                && lhs.isCurrentDestination == rhs.isCurrentDestination
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
    private(set) var lastProvenSceneIdentifier: RUMSceneIdentifier?
    private var activeOccurrence: ActiveOccurrence?
    private var lastStartedBindingGeneration: UInt64?
    private var requiresRemount = false
    private var restoresAppearanceOnReaderRemount = false
    private var retainedRouteHandoffGeneration: UInt64?

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

    /// Restores bookkeeping for a materialized navigation boundary that is not
    /// the container's current destination. This is used after the boundary's
    /// state temporarily lent scene proof and occurrence ownership to an
    /// initially restored top route. It never ends or creates an occurrence;
    /// active navigation remains under the interactive transition arbiter.
    @discardableResult
    func recordDormantNavigationBoundary(
        configuration: Configuration,
        attachment: Attachment
    ) -> Bool {
        guard activeOccurrence == nil, !requiresRemount else {
            return false
        }
        guard
            self.configuration == nil
                || configuration.bindingGeneration
                    >= (self.configuration?.bindingGeneration ?? 0)
        else {
            return false
        }

        var didMutate = false
        if self.configuration != configuration {
            self.configuration = configuration
            didMutate = true
        }
        if self.attachment != attachment {
            self.attachment = attachment
            didMutate = true
        }
        if isAppeared {
            isAppeared = false
            didMutate = true
        }
        if
            case .attached(let sceneIdentifier?) = attachment,
            lastProvenSceneIdentifier != sceneIdentifier {
            lastProvenSceneIdentifier = sceneIdentifier
            didMutate = true
        }
        finishMutation(didMutate)
        return true
    }

    /// Whether the navigation source may promote this already materialized
    /// boundary to the exact destination accepted by the customer's router.
    ///
    /// iOS 27 can reuse one mounted SwiftUI boundary when a Binding
    /// canonicalizes a native navigation proposal to another route. The
    /// proposed route is recorded as dormant first, and the reused boundary
    /// does not necessarily receive another `onAppear`. The same proof also
    /// lets a later accepted router generation supersede an older pending
    /// canonicalization. Keep both cases limited to an inactive dormant
    /// boundary and a binding generation that has never started from this
    /// state. Ordinary reconciliation requires unchanged concrete scene proof;
    /// only an exact source-accepted reader mount may relocate or recover a
    /// detached boundary.
    func canPromoteDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        allowsSceneMigration: Bool = false
    ) -> Bool {
        let hasMountedReaderProof = !requiresRemount
            && attachment == .attached(sceneIdentifier)
            && lastProvenSceneIdentifier == sceneIdentifier
        let hasSourceAuthorizedReaderProof: Bool
        switch attachment {
        case .detached:
            // The exact source-accepted ObserverView mount supplies concrete
            // scene proof even if the speculative boundary detached before it
            // was ever attached to a scene.
            hasSourceAuthorizedReaderProof = allowsSceneMigration
        case .attached(let attachedSceneIdentifier?):
            hasSourceAuthorizedReaderProof =
                allowsSceneMigration
                    && attachedSceneIdentifier != sceneIdentifier
                    && lastProvenSceneIdentifier == attachedSceneIdentifier
        case .attached(nil):
            hasSourceAuthorizedReaderProof = false
        }
        let hasConcreteReaderRecovery = requiresRemount
            && attachment == .detached
        return canResolveDormantNavigationBoundary(
            from: expectedDormantConfiguration,
            to: configuration
        ) && (
            hasMountedReaderProof
                || hasSourceAuthorizedReaderProof
                || hasConcreteReaderRecovery
        )
    }

    /// Whether a retained reader may commit the source-accepted key without
    /// publishing an occurrence. This accepts either the still-attached reader
    /// or a subsequent detached reconciliation, but both require the same last
    /// concrete scene proof.
    func canSettleDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        canResolveDormantNavigationBoundary(
            from: expectedDormantConfiguration,
            to: configuration
        ) && !requiresRemount
            && lastProvenSceneIdentifier == sceneIdentifier
            && (attachment == .attached(sceneIdentifier) || attachment == .detached)
    }

    private func canResolveDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration
    ) -> Bool {
        let advancesBinding = configuration.bindingGeneration
            > expectedDormantConfiguration.bindingGeneration
        let canonicalizesCurrentBinding = configuration.bindingGeneration
            == expectedDormantConfiguration.bindingGeneration
            && configuration.occurrenceKey
                != expectedDormantConfiguration.occurrenceKey
        return
            self.configuration == expectedDormantConfiguration
            && configuration.isCurrentDestination
            && !expectedDormantConfiguration.isCurrentDestination
            && (advancesBinding || canonicalizesCurrentBinding)
            && activeOccurrence == nil
            && (lastStartedBindingGeneration == nil
                || configuration.bindingGeneration
                    > (lastStartedBindingGeneration ?? 0))
            && !isAppeared
    }

    /// Atomically promotes a source-authorized dormant boundary. This is the
    /// only source-authorized exception to the ordinary binding fence, and it
    /// still participates in interactive-transition deferral by checking the
    /// revision captured by the arbiter.
    func promoteDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        expectedRevision: UInt64? = nil,
        allowsSceneMigration: Bool = false
    ) -> [Transition] {
        guard expectedRevision == nil || expectedRevision == revision else {
            return []
        }
        guard canPromoteDormantNavigationBoundary(
            from: expectedDormantConfiguration,
            to: configuration,
            in: sceneIdentifier,
            allowsSceneMigration: allowsSceneMigration
        ) else {
            return []
        }

        self.configuration = configuration
        attachment = .attached(sceneIdentifier)
        isAppeared = true
        lastProvenSceneIdentifier = sceneIdentifier
        requiresRemount = false
        restoresAppearanceOnReaderRemount = false
        guard let transition = start(in: sceneIdentifier) else {
            // The eligibility fence above guarantees a startable generation.
            // Stay non-authoritative if that invariant ever changes.
            isAppeared = false
            return []
        }
        finishMutation(true)
        return [transition]
    }

    /// Commits the accepted key without publishing an occurrence when the
    /// final interactive state is no longer both appeared and attached to the
    /// proved scene. This prevents a later accepted lifecycle callback from
    /// being rejected by the former speculative key's generation fence.
    func settleDormantNavigationPromotion(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64? = nil
    ) {
        guard expectedRevision == nil || expectedRevision == revision else {
            return
        }
        guard canSettleDormantNavigationBoundary(
            from: expectedDormantConfiguration,
            to: configuration,
            in: sceneIdentifier
        ) else {
            return
        }

        self.configuration = configuration
        if let attachment {
            self.attachment = attachment
            if case .attached(let sceneIdentifier?) = attachment {
                lastProvenSceneIdentifier = sceneIdentifier
            }
        }
        if attachment == .detached {
            self.isAppeared = false
            requiresRemount = true
            restoresAppearanceOnReaderRemount = true
            retainedRouteHandoffGeneration = nil
        } else if let isAppeared {
            self.isAppeared = isAppeared
        }
        finishMutation(true)
    }

    /// Preserves a source-authorized canonicalization when its scene
    /// disconnects before an interactive transition resolves. No occurrence is
    /// published for the disappearing scene; the accepted configuration and
    /// appearance proof are consumed only by a subsequent concrete reader
    /// mount.
    @discardableResult
    func preserveDormantNavigationPromotionAfterSceneDisconnect(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration
    ) -> Bool {
        let advancesBinding = configuration.bindingGeneration
            > expectedDormantConfiguration.bindingGeneration
        let canonicalizesCurrentBinding = configuration.bindingGeneration
            == expectedDormantConfiguration.bindingGeneration
            && configuration.occurrenceKey
                != expectedDormantConfiguration.occurrenceKey
        guard
            requiresRemount,
            activeOccurrence == nil,
            lastStartedBindingGeneration == nil
                || configuration.bindingGeneration
                    > (lastStartedBindingGeneration ?? 0),
            attachment == .detached,
            !isAppeared,
            self.configuration == expectedDormantConfiguration,
            !expectedDormantConfiguration.isCurrentDestination,
            configuration.isCurrentDestination,
            advancesBinding || canonicalizesCurrentBinding
        else {
            return false
        }

        self.configuration = configuration
        restoresAppearanceOnReaderRemount = true
        finishMutation(true)
        return true
    }

    /// Re-establishes scene proof for a hidden navigation boundary after its
    /// former scene disconnected. The navigation source has already established
    /// that this reader is not the accepted destination, so rearming must update
    /// bookkeeping without creating a view occurrence.
    @discardableResult
    func rearmDormantNavigationBoundaryAfterSceneDisconnect(
        configuration: Configuration,
        attachment: Attachment
    ) -> Bool {
        guard
            activeOccurrence == nil,
            requiresRemount,
            case .attached(let sceneIdentifier?) = attachment,
            self.configuration == nil
                || configuration.bindingGeneration
                    >= (self.configuration?.bindingGeneration ?? 0)
        else {
            return false
        }

        self.configuration = configuration
        self.attachment = attachment
        isAppeared = false
        lastProvenSceneIdentifier = sceneIdentifier
        retainedRouteHandoffGeneration = nil
        requiresRemount = false
        restoresAppearanceOnReaderRemount = false
        finishMutation(true)
        return true
    }

    /// Prepares an inactive replacement reader to own the source's last proven
    /// destination. Its dormant boundary can be from a newer binding snapshot
    /// whose destination descriptor has not arrived yet. A previously used
    /// reader is eligible only when its last-started generation belongs to that
    /// proven destination and its local state is either the destination or the
    /// source-validated boundary. This preflight never publishes a transition.
    @discardableResult
    func prepareSourceManagedNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration,
        boundaryConfiguration: Configuration
    ) -> Bool {
        let isNeverStarted = lifecycleGeneration == 0
            && lastStartedBindingGeneration == nil
        let isPreviouslyUsedForDestination = lifecycleGeneration > 0
            && lastStartedBindingGeneration == configuration.bindingGeneration
            && (self.configuration == configuration
                || self.configuration == boundaryConfiguration)
        guard
            activeOccurrence == nil,
            !isAppeared,
            isNeverStarted || isPreviouslyUsedForDestination
        else {
            return false
        }

        self.configuration = configuration
        attachment = .attached(sceneIdentifier)
        isAppeared = false
        lastProvenSceneIdentifier = sceneIdentifier
        retainedRouteHandoffGeneration = nil
        requiresRemount = false
        restoresAppearanceOnReaderRemount = false
        finishMutation(true)
        return true
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

    /// Starts an initial navigation destination using the scene proved by the
    /// container's root reader. The root can reconcile its own dormant
    /// configuration before that reader mounts, so this narrowly permits the
    /// never-started state to adopt the top destination from the same binding
    /// generation. Once any occurrence has started, ordinary generation fences
    /// remain authoritative.
    func mountInitialNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        if
            activeOccurrence == nil,
            lifecycleGeneration == 0,
            lastStartedBindingGeneration == nil,
            !requiresRemount,
            (self.configuration?.bindingGeneration ?? 0) <= configuration.bindingGeneration {
            self.configuration = nil
        }
        return mount(in: sceneIdentifier, configuration: configuration)
    }

    /// Recreates the same accepted navigation occurrence after the owning scene
    /// was torn down. `invalidateAfterSceneDisconnect` is the only operation
    /// that arms this same-generation exception; ordinary lifecycle callbacks
    /// remain unable to resurrect an ended occurrence.
    func mountCurrentNavigationDestinationAfterSceneDisconnect(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard canRecoverNavigationDestinationAfterSceneDisconnect(configuration) else {
            return []
        }

        requiresRemount = false
        restoresAppearanceOnReaderRemount = false
        attachment = .attached(sceneIdentifier)
        isAppeared = true
        lastProvenSceneIdentifier = sceneIdentifier
        lifecycleGeneration &+= 1
        let occurrence = ActiveOccurrence(
            identity: occurrenceIdentityGenerator(),
            configuration: configuration,
            lifecycleGeneration: lifecycleGeneration,
            sceneIdentifier: sceneIdentifier
        )
        activeOccurrence = occurrence
        finishMutation(true)
        return [.start(identity: occurrence.identity, sceneIdentifier: sceneIdentifier)]
    }

    /// Checks the exact configuration fence used for reliable reader recovery
    /// after scene teardown. The navigation source also uses this as a
    /// preflight before ending an occurrence owned by another reader.
    func canRecoverNavigationDestinationAfterSceneDisconnect(
        _ configuration: Configuration
    ) -> Bool {
        requiresRemount
            && activeOccurrence == nil
            && self.configuration == configuration
            && lastStartedBindingGeneration == configuration.bindingGeneration
    }

    /// Recreates an occurrence after the navigation source deliberately ended
    /// its same-generation owner while moving that boundary to another scene.
    /// This is intentionally narrower than an ordinary reader mount: only the
    /// source calls it immediately after balancing the prior occurrence.
    func remountSourceManagedNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard canRemountSourceManagedNavigationDestination(configuration) else {
            return []
        }

        attachment = .attached(sceneIdentifier)
        isAppeared = true
        lastProvenSceneIdentifier = sceneIdentifier
        lifecycleGeneration &+= 1
        let occurrence = ActiveOccurrence(
            identity: occurrenceIdentityGenerator(),
            configuration: configuration,
            lifecycleGeneration: lifecycleGeneration,
            sceneIdentifier: sceneIdentifier
        )
        activeOccurrence = occurrence
        finishMutation(true)
        return [.start(identity: occurrence.identity, sceneIdentifier: sceneIdentifier)]
    }

    /// Checks the narrow same-generation restart used by a navigation source
    /// after it has balanced the occurrence currently owned by another reader.
    /// Keeping this preflight separate prevents the source from stopping the
    /// live owner before discovering that the replacement cannot take over.
    func canRemountSourceManagedNavigationDestination(
        _ configuration: Configuration
    ) -> Bool {
        !requiresRemount
            && activeOccurrence == nil
            && !isAppeared
            && lifecycleGeneration > 0
            && self.configuration == configuration
            && lastStartedBindingGeneration == configuration.bindingGeneration
    }

    func mountFromReader(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard acceptsReaderMount else {
            return []
        }
        return reconcile(
            configuration: configuration,
            attachment: .attached(sceneIdentifier),
            isAppeared: appearanceForReaderMount,
            expectedRevision: nil,
            allowsRemount: true
        )
    }

    func mountFromInitialTrait(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard acceptsInitialTraitMount else {
            return []
        }
        return mount(in: sceneIdentifier, configuration: configuration)
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
        if
            let configuration,
            let retainedRouteHandoffGeneration,
            configuration.bindingGeneration > retainedRouteHandoffGeneration {
            self.retainedRouteHandoffGeneration = nil
        }
        if
            attachment == nil,
            isAppeared == false,
            let retainedRouteHandoffGeneration,
            activeOccurrence?.configuration?.bindingGeneration
                == retainedRouteHandoffGeneration {
            // A navigation-owned reveal runs before SwiftUI decides whether it
            // can reuse the old subtree. If SwiftUI replaces that subtree, its
            // final disappearance must not close the occurrence before the new
            // platform reader can adopt it.
            return []
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
            if
                case .attached(let sceneIdentifier?) = attachment,
                lastProvenSceneIdentifier != sceneIdentifier {
                lastProvenSceneIdentifier = sceneIdentifier
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

    /// Scene proof available to a navigation-owned reveal. A hidden retained
    /// route is routinely detached from its window before the path binding is
    /// committed, so it may use its last concrete scene. An attached reader
    /// with no scene is ambiguous and must stay unresolved in a multi-window
    /// application.
    var retainedRouteSceneIdentifier: RUMSceneIdentifier? {
        switch attachment {
        case .attached(let sceneIdentifier?):
            return sceneIdentifier
        case .attached(nil):
            return nil
        case .detached:
            return lastProvenSceneIdentifier
        }
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

    /// Keeps a navigation-owned occurrence alive while SwiftUI resolves whether
    /// the retained route will reuse this tracking state or mount a replacement.
    func prepareForRetainedRouteHandoff(
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard
            let activeOccurrence,
            activeOccurrence.configuration == configuration,
            activeOccurrence.sceneIdentifier == sceneIdentifier,
            isAppeared,
            !requiresRemount
        else {
            return false
        }
        retainedRouteHandoffGeneration = configuration.bindingGeneration
        finishMutation(true)
        return true
    }

    /// Transfers an already published occurrence to a replacement SwiftUI state
    /// without publishing another start. The replacement owns all later
    /// lifecycle callbacks, including the matching stop.
    func transferRetainedRouteOccurrence(
        to target: RUMViewTrackingState,
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard
            self !== target,
            retainedRouteHandoffGeneration == configuration.bindingGeneration,
            let activeOccurrence,
            activeOccurrence.configuration == configuration,
            activeOccurrence.sceneIdentifier == sceneIdentifier,
            target.activeOccurrence == nil,
            target.lifecycleGeneration == 0,
            target.lastStartedBindingGeneration == nil,
            !target.requiresRemount,
            target.configuration == nil || target.configuration == configuration,
            target.attachment == .detached
                || target.attachment == .attached(sceneIdentifier)
        else {
            return false
        }

        target.lifecycleGeneration &+= 1
        target.configuration = configuration
        target.attachment = .attached(sceneIdentifier)
        target.isAppeared = true
        target.activeOccurrence = ActiveOccurrence(
            identity: activeOccurrence.identity,
            configuration: configuration,
            lifecycleGeneration: target.lifecycleGeneration,
            sceneIdentifier: sceneIdentifier
        )
        target.lastStartedBindingGeneration = configuration.bindingGeneration
        target.lastProvenSceneIdentifier = sceneIdentifier
        target.finishMutation(true)

        self.activeOccurrence = nil
        self.attachment = .detached
        self.isAppeared = false
        retainedRouteHandoffGeneration = nil
        finishMutation(true)
        return true
    }

    /// Moves a provisional source-owned occurrence to a replacement platform
    /// reader without publishing another start. Unlike retained-route adoption,
    /// the replacement state may already contain the donor boundary's dormant
    /// configuration; the source has validated that boundary before calling.
    func transferSourceManagedNavigationDestination(
        to target: RUMViewTrackingState,
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        let isUnstartedTarget = target.lifecycleGeneration == 0
            && target.lastStartedBindingGeneration == nil
        let isReusableExactTarget = target
            .canRemountSourceManagedNavigationDestination(configuration)
            || target.canRecoverNavigationDestinationAfterSceneDisconnect(configuration)
        guard
            self !== target,
            let activeOccurrence,
            activeOccurrence.configuration == configuration,
            activeOccurrence.sceneIdentifier == sceneIdentifier,
            target.activeOccurrence == nil,
            isUnstartedTarget || isReusableExactTarget,
            target.attachment == .detached
                || target.attachment == .attached(sceneIdentifier)
        else {
            return false
        }

        target.lifecycleGeneration &+= 1
        target.configuration = configuration
        target.attachment = .attached(sceneIdentifier)
        target.isAppeared = true
        target.activeOccurrence = ActiveOccurrence(
            identity: activeOccurrence.identity,
            configuration: configuration,
            lifecycleGeneration: target.lifecycleGeneration,
            sceneIdentifier: sceneIdentifier
        )
        target.lastStartedBindingGeneration = configuration.bindingGeneration
        target.lastProvenSceneIdentifier = sceneIdentifier
        target.requiresRemount = false
        target.restoresAppearanceOnReaderRemount = false
        target.finishMutation(true)

        self.activeOccurrence = nil
        self.attachment = .detached
        self.isAppeared = false
        retainedRouteHandoffGeneration = nil
        finishMutation(true)
        return true
    }

    func settleRetainedRouteHandoff(
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard
            retainedRouteHandoffGeneration == configuration.bindingGeneration,
            activeOccurrence?.configuration == configuration,
            activeOccurrence?.sceneIdentifier == sceneIdentifier
        else {
            return false
        }
        retainedRouteHandoffGeneration = nil
        finishMutation(true)
        return true
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
            committedSceneIdentifier = attachedSceneIdentifier ?? lastProvenSceneIdentifier
        } else {
            committedSceneIdentifier = lastProvenSceneIdentifier
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
        lastProvenSceneIdentifier = nil
        retainedRouteHandoffGeneration = nil
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
        retainedRouteHandoffGeneration = nil
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

#if os(iOS)
private protocol RUMSwiftUIAutomaticViewAuthorityState: AnyObject {
    var isAutomaticViewAuthorityActive: Bool { get }
}

extension RUMViewTrackingState: RUMSwiftUIAutomaticViewAuthorityState {
    fileprivate var isAutomaticViewAuthorityActive: Bool { isAppeared }
}

/// Keeps automatic SwiftUI discovery suppressed for a mounted semantic
/// presentation subtree without publishing a second RUM view lifecycle. The
/// navigation owner remains responsible for starting and stopping the semantic
/// occurrence; this state follows the platform subtree through its dismissal.
internal final class RUMSwiftUIAutomaticViewSuppressionState: RUMSwiftUIAutomaticViewAuthorityState {
    private(set) var isActive = false

    fileprivate var isAutomaticViewAuthorityActive: Bool { isActive }

    func appear() {
        isActive = true
    }

    func disappear() {
        isActive = false
    }
}

/// Tracks active explicit SwiftUI view boundaries so automatic controller
/// discovery can stay enabled without creating a duplicate RUM view for the
/// same subtree. Entries are weak and scoped by actual view containment rather
/// than by scene, leaving unrelated containers in the same window eligible for
/// automatic tracking.
internal final class RUMSwiftUIViewAuthorityRegistry {
    private final class WeakEntry {
        weak var observer: RUMSceneIdentifierReader.ObserverView?
        weak var authorityState: (any RUMSwiftUIAutomaticViewAuthorityState)?

        init(
            observer: RUMSceneIdentifierReader.ObserverView,
            authorityState: any RUMSwiftUIAutomaticViewAuthorityState
        ) {
            self.observer = observer
            self.authorityState = authorityState
        }
    }

    private var entries: [WeakEntry] = []

    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        trackingState: RUMViewTrackingState
    ) {
        register(observer: observer, authorityState: trackingState)
    }

    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        suppressionState: RUMSwiftUIAutomaticViewSuppressionState
    ) {
        register(observer: observer, authorityState: suppressionState)
    }

    private func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        authorityState: any RUMSwiftUIAutomaticViewAuthorityState
    ) {
        entries.removeAll { entry in
            entry.observer == nil || entry.authorityState == nil || entry.observer === observer
        }
        entries.append(WeakEntry(observer: observer, authorityState: authorityState))
    }

    func isAutomaticViewSuppressed(for viewController: UIViewController) -> Bool {
        entries.removeAll { $0.observer == nil || $0.authorityState == nil }
        guard let candidateView = viewController.viewIfLoaded else {
            return false
        }

        return entries.contains { entry in
            guard
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
#endif

#if os(iOS) || os(visionOS)
/// Experimental navigation-owned signal used to establish the initially
/// restored destination and to reveal an already materialized route before
/// SwiftUI replays outer lifecycle callbacks. The source is also the
/// container-level generation fence: a delayed boundary from an older router
/// snapshot must not regain view authority merely because SwiftUI created a new
/// local tracking state for it.
@MainActor
internal final class RUMSwiftUINavigationOccurrenceSource {
    enum DestinationChange {
        case initial(requiresBootstrap: Bool)
        case unchanged
        case replacement
        case retainedReveal
    }

    enum CandidateDisposition: Equatable {
        case handled
        case allowOrdinaryMount
        case promoteDormantBoundary(
            expected: RUMViewTrackingState.Configuration,
            accepted: RUMViewTrackingState.Configuration
        )
        case recordDormant
        case rejectStale
    }

    private struct DestinationIdentity: Equatable {
        let occurrenceKey: RUMViewOccurrenceKey
        let bindingGeneration: UInt64
    }

    private struct PendingRevealedRoute {
        let configuration: RUMViewTrackingState.Configuration
        let sceneIdentifier: RUMSceneIdentifier
        let state: RUMViewTrackingState
    }

    /// The initial restored destination can be started using scene proof from a
    /// different boundary (normally the root) before its own platform reader is
    /// materialized. Keep the published occurrence under container ownership
    /// until the accepted boundary adopts it, changes, disconnects, or the
    /// container is removed.
    private struct ManagedInitialOccurrence {
        let configuration: RUMViewTrackingState.Configuration
        let boundaryConfiguration: RUMViewTrackingState.Configuration
        let boundaryAttachment: RUMViewTrackingState.Attachment
        let sceneIdentifier: RUMSceneIdentifier
        let state: RUMViewTrackingState
        let isAdopted: Bool
    }

    private final class WeakRegistration {
        weak var registration: RUMSwiftUINavigationOccurrenceRegistration?
        let callbackEpoch: UInt64

        init(
            registration: RUMSwiftUINavigationOccurrenceRegistration,
            callbackEpoch: UInt64
        ) {
            self.registration = registration
            self.callbackEpoch = callbackEpoch
        }
    }

    private var registrations: [WeakRegistration] = []
    private var pendingRevealedRoute: PendingRevealedRoute?
    private var acceptedDestinationIdentity: DestinationIdentity?
    private var acceptedDestinationConfiguration: RUMViewTrackingState.Configuration?
    private var managedInitialOccurrence: ManagedInitialOccurrence?
    private var requiresInitialBootstrap = false
    private var awaitsCommittedRevealConfiguration = false

    var isInitialDestinationPending: Bool {
        requiresInitialBootstrap
    }

    var needsInitialDestinationReconciliation: Bool {
        acceptedDestinationConfiguration == nil
    }

    /// Records the customer's accepted router destination before platform
    /// lifecycle callbacks can arrive. Descriptor reconciliation follows from
    /// `RUMNavigationStack.body`, but the occurrence key and generation are
    /// enough to reject delayed boundaries immediately.
    func acceptDestination(
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        change: DestinationChange
    ) {
        let nextIdentity = DestinationIdentity(
            occurrenceKey: occurrenceKey,
            bindingGeneration: bindingGeneration
        )
        if acceptedDestinationIdentity != nextIdentity {
            acceptedDestinationConfiguration = nil
        }
        acceptedDestinationIdentity = nextIdentity

        switch change {
        case .initial(let requiresBootstrap):
            requiresInitialBootstrap = requiresBootstrap
        case .unchanged:
            break
        case .replacement:
            // A replacement route must prove materialization before it can
            // displace a provisional initial occurrence. The updated identity
            // fence still rejects every boundary from the previous snapshot.
            awaitsCommittedRevealConfiguration = false
            if managedInitialOccurrence?.isAdopted == true {
                // Once the initial destination is owned by its real boundary,
                // subsequent pushes/replacements return to the ordinary
                // transition arbiter (including interactive cancellation).
                managedInitialOccurrence = nil
                requiresInitialBootstrap = false
            }
        case .retainedReveal:
            if let managedInitialOccurrence, !managedInitialOccurrence.isAdopted {
                // The revealed destination is already materialized underneath
                // the provisional owner. Reconcile it synchronously once its
                // current descriptor is supplied by the container body.
                awaitsCommittedRevealConfiguration = true
            } else {
                managedInitialOccurrence = nil
                requiresInitialBootstrap = false
                _ = revealRetainedRoute(
                    occurrenceKey: occurrenceKey,
                    bindingGeneration: bindingGeneration
                )
            }
        }
    }

    /// Supplies the descriptor for the latest accepted destination. When a pop
    /// happens before the initial top adopts its provisional occurrence, this
    /// changes that occurrence into the already-materialized revealed boundary
    /// in the same synchronous router turn.
    @discardableResult
    func reconcileCurrentDestination(
        configuration: RUMViewTrackingState.Configuration,
        viewsHandler: RUMViewsHandler?
    ) -> [RUMViewTrackingState.Transition] {
        guard matchesAcceptedDestination(configuration) else {
            return []
        }
        acceptedDestinationConfiguration = configuration

        guard awaitsCommittedRevealConfiguration else {
            return []
        }
        awaitsCommittedRevealConfiguration = false

        guard let owner = managedInitialOccurrence else {
            _ = revealRetainedRoute(
                occurrenceKey: configuration.occurrenceKey,
                bindingGeneration: configuration.bindingGeneration
            )
            return []
        }

        _ = owner.state.settleRetainedRouteHandoff(
            configuration: owner.configuration,
            sceneIdentifier: owner.sceneIdentifier
        )
        let transitions = owner.state.reconcile(
            configuration: configuration,
            attachment: .attached(owner.sceneIdentifier),
            isAppeared: true
        )
        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: owner.state,
            fallback: configuration.descriptor,
            to: viewsHandler
        )

        guard owner.state.activeLifecycleGeneration != nil else {
            managedInitialOccurrence = nil
            return transitions
        }
        let isAdopted = owner.boundaryConfiguration.occurrenceKey
            == configuration.occurrenceKey
        managedInitialOccurrence = ManagedInitialOccurrence(
            configuration: configuration,
            boundaryConfiguration: owner.boundaryConfiguration,
            boundaryAttachment: .attached(owner.sceneIdentifier),
            sceneIdentifier: owner.sceneIdentifier,
            state: owner.state,
            isAdopted: isAdopted
        )
        requiresInitialBootstrap = !isAdopted
        return transitions
    }

    /// Resolves one materialized boundary against the container's accepted
    /// destination. A non-current boundary may lend scene proof only while the
    /// initial restored destination has no owner. All other key/generation
    /// mismatches are stale and must not fall through to an ordinary mount.
    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        viewsHandler: RUMViewsHandler?,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            allowsDormantBoundaryPromotion: false,
            viewsHandler: viewsHandler,
            process: process
        )
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        allowsDormantBoundaryPromotion: Bool,
        viewsHandler: RUMViewsHandler?,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            isReaderMount: true,
            allowsDormantBoundaryPromotion: allowsDormantBoundaryPromotion,
            viewsHandler: viewsHandler,
            process: process
        )
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        viewsHandler: RUMViewsHandler?,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            isReaderMount: isReaderMount,
            allowsDormantBoundaryPromotion: false,
            viewsHandler: viewsHandler,
            process: process
        )
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        allowsDormantBoundaryPromotion: Bool,
        viewsHandler: RUMViewsHandler?,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        if !candidateConfiguration.isCurrentDestination {
            if
                let owner = managedInitialOccurrence,
                owner.boundaryConfiguration.occurrenceKey
                    == candidateConfiguration.occurrenceKey {
                return resolveManagedInitialBoundary(
                    owner: owner,
                    candidateConfiguration: candidateConfiguration,
                    sceneIdentifier: sceneIdentifier,
                    state: state,
                    isReaderMount: isReaderMount,
                    viewsHandler: viewsHandler,
                    process: process
                )
            }

            guard let acceptedDestinationConfiguration else {
                return .recordDormant
            }
            let mayLendInitialScene = requiresInitialBootstrap
                && managedInitialOccurrence == nil
                && candidateConfiguration.bindingGeneration
                    == acceptedDestinationConfiguration.bindingGeneration
            guard mayLendInitialScene else {
                return .recordDormant
            }
            startManagedInitialOccurrence(
                configuration: acceptedDestinationConfiguration,
                boundaryConfiguration: candidateConfiguration,
                sceneIdentifier: sceneIdentifier,
                state: state,
                viewsHandler: viewsHandler,
                process: process
            )
            return .handled
        }

        guard
            let acceptedDestinationConfiguration,
            matchesAcceptedDestination(candidateConfiguration)
        else {
            return .rejectStale
        }

        let candidateMatches = candidateConfiguration == acceptedDestinationConfiguration
        guard candidateMatches else {
            return .rejectStale
        }

        if candidateMatches,
           let pendingDisposition = consumePendingRevealedRoute(
               configuration: candidateConfiguration,
               sceneIdentifier: sceneIdentifier,
               into: state,
               viewsHandler: viewsHandler
           ) {
            return pendingDisposition
        }

        if let owner = managedInitialOccurrence {
            if owner.configuration != acceptedDestinationConfiguration
                || owner.sceneIdentifier != sceneIdentifier {
                let movedSameDestinationToAnotherScene = owner.configuration
                    == acceptedDestinationConfiguration
                    && owner.sceneIdentifier != sceneIdentifier
                stopManagedInitialOccurrence(owner, viewsHandler: viewsHandler)
                if
                    owner.configuration != acceptedDestinationConfiguration,
                    !owner.isAdopted,
                    owner.state !== state {
                    _ = owner.state.recordDormantNavigationBoundary(
                        configuration: owner.boundaryConfiguration,
                        attachment: owner.boundaryAttachment
                    )
                }
                managedInitialOccurrence = nil
                startManagedInitialOccurrence(
                    configuration: acceptedDestinationConfiguration,
                    boundaryConfiguration: candidateConfiguration,
                    sceneIdentifier: sceneIdentifier,
                    state: state,
                    viewsHandler: viewsHandler,
                    allowsSameGenerationRemount: movedSameDestinationToAnotherScene,
                    process: process
                )
                return .handled
            }

            if owner.state === state {
                if state.needsReaderRemount {
                    managedInitialOccurrence = nil
                    startManagedInitialOccurrence(
                        configuration: acceptedDestinationConfiguration,
                        boundaryConfiguration: candidateConfiguration,
                        sceneIdentifier: sceneIdentifier,
                        state: state,
                        viewsHandler: viewsHandler,
                        process: process
                    )
                    return .handled
                }
                _ = state.settleRetainedRouteHandoff(
                    configuration: owner.configuration,
                    sceneIdentifier: owner.sceneIdentifier
                )
                managedInitialOccurrence = ManagedInitialOccurrence(
                    configuration: owner.configuration,
                    boundaryConfiguration: candidateConfiguration,
                    boundaryAttachment: .attached(sceneIdentifier),
                    sceneIdentifier: owner.sceneIdentifier,
                    state: state,
                    isAdopted: candidateMatches
                )
                if candidateMatches {
                    requiresInitialBootstrap = false
                }
                return .handled
            }

            if owner.state.prepareForRetainedRouteHandoff(
                configuration: owner.configuration,
                sceneIdentifier: owner.sceneIdentifier
            ), owner.state.transferRetainedRouteOccurrence(
                to: state,
                configuration: owner.configuration,
                sceneIdentifier: owner.sceneIdentifier
            ) {
                managedInitialOccurrence = ManagedInitialOccurrence(
                    configuration: owner.configuration,
                    boundaryConfiguration: candidateConfiguration,
                    boundaryAttachment: .attached(sceneIdentifier),
                    sceneIdentifier: owner.sceneIdentifier,
                    state: state,
                    isAdopted: candidateMatches
                )
                if candidateMatches {
                    requiresInitialBootstrap = false
                }
                return .handled
            }

            // A replacement state that cannot accept the exact occurrence must
            // never create a second view beside it. Keep the proven owner.
            return .rejectStale
        }

        guard requiresInitialBootstrap else {
            if
                allowsDormantBoundaryPromotion,
                let dormantConfiguration = state.configuration,
                state.canPromoteDormantNavigationBoundary(
                    from: dormantConfiguration,
                    to: acceptedDestinationConfiguration,
                    in: sceneIdentifier,
                    allowsSceneMigration: isReaderMount
                ) {
                return .promoteDormantBoundary(
                    expected: dormantConfiguration,
                    accepted: acceptedDestinationConfiguration
                )
            }
            return .allowOrdinaryMount
        }
        startManagedInitialOccurrence(
            configuration: acceptedDestinationConfiguration,
            boundaryConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            viewsHandler: viewsHandler,
            process: process
        )
        return .handled
    }

    private func resolveManagedInitialBoundary(
        owner: ManagedInitialOccurrence,
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        viewsHandler: RUMViewsHandler?,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard !owner.isAdopted else {
            return .rejectStale
        }
        let candidateGeneration = candidateConfiguration.bindingGeneration
        let boundaryGeneration = owner.boundaryConfiguration.bindingGeneration
        guard candidateGeneration >= boundaryGeneration else {
            return .rejectStale
        }
        if candidateGeneration > boundaryGeneration {
            guard candidateGeneration == acceptedDestinationIdentity?.bindingGeneration else {
                return .rejectStale
            }
        }

        let nextBoundaryConfiguration = candidateGeneration > boundaryGeneration
            ? candidateConfiguration
            : owner.boundaryConfiguration
        let staysInOwningScene = owner.sceneIdentifier == sceneIdentifier
        if !isReaderMount {
            managedInitialOccurrence = ManagedInitialOccurrence(
                configuration: owner.configuration,
                boundaryConfiguration: nextBoundaryConfiguration,
                boundaryAttachment: owner.boundaryAttachment,
                sceneIdentifier: owner.sceneIdentifier,
                state: owner.state,
                isAdopted: false
            )
            return .handled
        }

        // A replacement reader may store a newer donor boundary while the
        // source still owns the last proven destination descriptor. Prepare
        // that never-started reader with the proven destination before any
        // transfer or stop; the source retains `nextBoundaryConfiguration`.
        // Ordinary lifecycle callbacks cannot take this path.
        if
            state !== owner.state,
            !state.prepareSourceManagedNavigationDestination(
                in: sceneIdentifier,
                configuration: owner.configuration,
                boundaryConfiguration: nextBoundaryConfiguration
            ) {
            return .rejectStale
        }

        if staysInOwningScene, owner.state === state {
            if state.needsReaderRemount {
                managedInitialOccurrence = nil
                startManagedInitialOccurrence(
                    configuration: owner.configuration,
                    boundaryConfiguration: nextBoundaryConfiguration,
                    sceneIdentifier: sceneIdentifier,
                    state: state,
                    viewsHandler: viewsHandler,
                    process: process
                )
            } else {
                managedInitialOccurrence = ManagedInitialOccurrence(
                    configuration: owner.configuration,
                    boundaryConfiguration: nextBoundaryConfiguration,
                    boundaryAttachment: .attached(sceneIdentifier),
                    sceneIdentifier: owner.sceneIdentifier,
                    state: owner.state,
                    isAdopted: false
                )
            }
            return .handled
        }

        if staysInOwningScene, owner.state.activeLifecycleGeneration != nil {
            guard owner.state.transferSourceManagedNavigationDestination(
                to: state,
                configuration: owner.configuration,
                sceneIdentifier: sceneIdentifier
            ) else {
                return .rejectStale
            }
            managedInitialOccurrence = ManagedInitialOccurrence(
                configuration: owner.configuration,
                boundaryConfiguration: nextBoundaryConfiguration,
                boundaryAttachment: .attached(sceneIdentifier),
                sceneIdentifier: sceneIdentifier,
                state: state,
                isAdopted: false
            )
            return .handled
        }

        let allowsSameGenerationRemount = owner.state === state
            || state.canRemountSourceManagedNavigationDestination(owner.configuration)
        let canRecoverAfterSceneDisconnect = state
            .canRecoverNavigationDestinationAfterSceneDisconnect(owner.configuration)
        if
            state.activeLifecycleGeneration != nil,
            owner.state !== state {
            return .rejectStale
        }
        if
            state.lifecycleGeneration > 0,
            owner.state !== state,
            !allowsSameGenerationRemount,
            !canRecoverAfterSceneDisconnect {
            return .rejectStale
        }

        if owner.state.activeLifecycleGeneration != nil {
            stopManagedInitialOccurrence(owner, viewsHandler: viewsHandler)
        }
        managedInitialOccurrence = nil
        startManagedInitialOccurrence(
            configuration: owner.configuration,
            boundaryConfiguration: nextBoundaryConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            viewsHandler: viewsHandler,
            allowsSameGenerationRemount: allowsSameGenerationRemount,
            process: process
        )
        return managedInitialOccurrence == nil ? .rejectStale : .handled
    }

    /// Protects a provisional destination from lifecycle callbacks emitted by
    /// the non-current boundary that lent it scene proof. A refreshed donor may
    /// update its own dormant bookkeeping, but it cannot replace or stop the
    /// visible destination before the accepted boundary materializes.
    func retainsManagedInitialOccurrence(
        for boundaryConfiguration: RUMViewTrackingState.Configuration,
        state: RUMViewTrackingState,
        attachment: RUMViewTrackingState.Attachment? = nil
    ) -> Bool {
        guard
            !boundaryConfiguration.isCurrentDestination,
            let owner = managedInitialOccurrence,
            !owner.isAdopted,
            owner.state === state
        else {
            return false
        }

        guard owner.boundaryConfiguration.occurrenceKey
            == boundaryConfiguration.occurrenceKey else {
            return false
        }

        let candidateGeneration = boundaryConfiguration.bindingGeneration
        let currentGeneration = owner.boundaryConfiguration.bindingGeneration
        let isAcceptedGenerationRefresh = candidateGeneration > currentGeneration
            && candidateGeneration == acceptedDestinationIdentity?.bindingGeneration
        let canUpdateBoundary = candidateGeneration == currentGeneration
            || isAcceptedGenerationRefresh
        guard canUpdateBoundary else {
            // Older or not-yet-accepted callbacks for the leased donor are stale,
            // but still belong to source-owned lifecycle and must not fall back
            // to the state's older generation fence.
            return true
        }
        if
            case .attached(let sceneIdentifier?) = attachment,
            sceneIdentifier != owner.sceneIdentifier {
            // A concrete reader mount will resolve the scene migration. Trait or
            // reconciliation updates cannot move a source-owned occurrence.
            return true
        }

        managedInitialOccurrence = ManagedInitialOccurrence(
            configuration: owner.configuration,
            boundaryConfiguration: isAcceptedGenerationRefresh
                ? boundaryConfiguration
                : owner.boundaryConfiguration,
            boundaryAttachment: attachment ?? owner.boundaryAttachment,
            sceneIdentifier: owner.sceneIdentifier,
            state: owner.state,
            isAdopted: false
        )
        return true
    }

    /// Balances source-managed initial or retained occurrences if the navigation
    /// container itself is removed. This is intentionally called from an outer
    /// attachment reader rather than the root content's `onDisappear`, which is
    /// also expected during an ordinary push.
    @discardableResult
    func cancelNavigationOwnedOccurrences(
        viewsHandler: RUMViewsHandler?
    ) -> [RUMViewTrackingState.Transition] {
        var stoppedIdentities: Set<String> = []
        var transitions: [RUMViewTrackingState.Transition] = []
        if let owner = managedInitialOccurrence {
            transitions += stopManagedInitialOccurrence(
                owner,
                viewsHandler: viewsHandler,
                stoppedIdentities: &stoppedIdentities
            )
        }
        if let pendingRevealedRoute {
            transitions += stopNavigationOwnedOccurrence(
                state: pendingRevealedRoute.state,
                configuration: pendingRevealedRoute.configuration,
                sceneIdentifier: pendingRevealedRoute.sceneIdentifier,
                viewsHandler: viewsHandler,
                stoppedIdentities: &stoppedIdentities
            )
        }
        managedInitialOccurrence = nil
        pendingRevealedRoute = nil
        requiresInitialBootstrap = false
        awaitsCommittedRevealConfiguration = false
        return transitions
    }

    /// Mirrors scene-stack teardown without publishing a duplicate stop. The
    /// views handler owns the disconnect command; this only releases the
    /// container's stale lease so another scene can become authoritative.
    func sceneDidDisconnect(_ sceneIdentifier: RUMSceneIdentifier) {
        if
            let owner = managedInitialOccurrence,
            owner.sceneIdentifier == sceneIdentifier,
            owner.state.activeLifecycleGeneration == nil {
            managedInitialOccurrence = nil
            requiresInitialBootstrap = acceptedDestinationConfiguration != nil
        }
        if
            let pendingRevealedRoute,
            pendingRevealedRoute.sceneIdentifier == sceneIdentifier,
            pendingRevealedRoute.state.activeLifecycleGeneration == nil {
            self.pendingRevealedRoute = nil
        }
    }

    func reconcileOwnerState(_ state: RUMViewTrackingState) {
        guard
            let owner = managedInitialOccurrence,
            owner.state === state,
            state.activeLifecycleGeneration == nil
        else {
            return
        }
        managedInitialOccurrence = nil
    }

    func isAcceptedBoundary(
        _ configuration: RUMViewTrackingState.Configuration
    ) -> Bool {
        matchesAcceptedDestination(configuration)
    }

    /// Resolves a boundary reused by SwiftUI after the customer's path binding
    /// canonicalizes a native proposal. This runs while SwiftUI evaluates the
    /// accepted destination's modifier, before outer lifecycle callbacks.
    ///
    /// The environment trait is only a timing signal here. Scene authority still
    /// comes from the same boundary's prior concrete reader attachment. A stale
    /// trait therefore cannot recover a disconnected boundary or move it to a
    /// different scene; those cases continue to require an ObserverView mount.
    func resolveDormantCandidateFromEnvironmentTrait(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState
    ) -> CandidateDisposition {
        guard candidateConfiguration.isCurrentDestination else {
            return .recordDormant
        }
        guard
            let acceptedDestinationConfiguration,
            matchesAcceptedDestination(candidateConfiguration),
            candidateConfiguration == acceptedDestinationConfiguration
        else {
            return .rejectStale
        }
        guard
            !requiresInitialBootstrap,
            managedInitialOccurrence == nil,
            pendingRevealedRoute == nil,
            state.attachment == .attached(sceneIdentifier),
            !state.needsReaderRemount,
            let dormantConfiguration = state.configuration,
            state.canPromoteDormantNavigationBoundary(
                from: dormantConfiguration,
                to: acceptedDestinationConfiguration,
                in: sceneIdentifier
            )
        else {
            return .allowOrdinaryMount
        }
        return .promoteDormantBoundary(
            expected: dormantConfiguration,
            accepted: acceptedDestinationConfiguration
        )
    }

    fileprivate func register(
        _ registration: RUMSwiftUINavigationOccurrenceRegistration,
        callbackEpoch: UInt64
    ) {
        registrations.removeAll {
            $0.registration == nil || $0.registration === registration
        }
        registrations.append(
            WeakRegistration(
                registration: registration,
                callbackEpoch: callbackEpoch
            )
        )
    }

    fileprivate func unregister(_ registration: RUMSwiftUINavigationOccurrenceRegistration) {
        registrations.removeAll { $0.registration == nil || $0.registration === registration }
    }

    /// Reveals a route retained below the current navigation destination. A
    /// registration may have published an earlier occurrence or may only have
    /// retained materialization and scene proof while it was hidden.
    @discardableResult
    func revealRetainedRoute(
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64
    ) -> Bool {
        registrations.removeAll { $0.registration == nil }
        clearPendingRevealedRoute()
        for entry in registrations.reversed() {
            guard let registration = entry.registration else {
                continue
            }
            guard let sceneIdentifier = registration.revealRetainedRoute(
                from: self,
                occurrenceKey: occurrenceKey,
                bindingGeneration: bindingGeneration,
                expectedCallbackEpoch: entry.callbackEpoch
            ), let state = registration.trackingState,
            let descriptor = registration.descriptor else {
                continue
            }
            let configuration = RUMViewTrackingState.Configuration(
                occurrenceKey: occurrenceKey,
                bindingGeneration: bindingGeneration,
                descriptor: descriptor,
                isCurrentDestination: true
            )
            if
                state.prepareForRetainedRouteHandoff(
                    configuration: configuration,
                    sceneIdentifier: sceneIdentifier
                ) {
                pendingRevealedRoute = PendingRevealedRoute(
                    configuration: configuration,
                    sceneIdentifier: sceneIdentifier,
                    state: state
                )
            }
            return true
        }
        return false
    }

    /// Lets a newly mounted SwiftUI subtree take ownership of a view occurrence
    /// that was already published by the navigation-owned source.
    func consumeRevealedRoute(
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        into state: RUMViewTrackingState
    ) -> Bool {
        consumePendingRevealedRoute(
            configuration: configuration,
            sceneIdentifier: sceneIdentifier,
            into: state,
            viewsHandler: nil
        ) == .handled
    }

    private func matchesAcceptedDestination(
        _ configuration: RUMViewTrackingState.Configuration
    ) -> Bool {
        acceptedDestinationIdentity == DestinationIdentity(
            occurrenceKey: configuration.occurrenceKey,
            bindingGeneration: configuration.bindingGeneration
        )
    }

    private func startManagedInitialOccurrence(
        configuration: RUMViewTrackingState.Configuration,
        boundaryConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        viewsHandler: RUMViewsHandler?,
        allowsSameGenerationRemount: Bool = false,
        process: (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) {
        if state.activeLifecycleGeneration == nil, state.needsReaderRemount {
            let transitions = state.mountCurrentNavigationDestinationAfterSceneDisconnect(
                in: sceneIdentifier,
                configuration: configuration
            )
            RUMSwiftUIViewTransitionPublisher.publish(
                transitions,
                state: state,
                fallback: configuration.descriptor,
                to: viewsHandler
            )
            if state.activeLifecycleGeneration == nil {
                process(configuration, sceneIdentifier)
            }
        } else if
            state.activeLifecycleGeneration == nil,
            allowsSameGenerationRemount,
            state.lifecycleGeneration > 0 {
            let transitions = state.remountSourceManagedNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
            RUMSwiftUIViewTransitionPublisher.publish(
                transitions,
                state: state,
                fallback: configuration.descriptor,
                to: viewsHandler
            )
        } else {
            process(configuration, sceneIdentifier)
        }
        guard
            state.configuration == configuration,
            state.activeLifecycleGeneration != nil,
            state.sceneIdentifier == sceneIdentifier
        else {
            return
        }
        let isAdopted = boundaryConfiguration.isCurrentDestination
            && boundaryConfiguration == configuration
        managedInitialOccurrence = ManagedInitialOccurrence(
            configuration: configuration,
            boundaryConfiguration: boundaryConfiguration,
            boundaryAttachment: .attached(sceneIdentifier),
            sceneIdentifier: sceneIdentifier,
            state: state,
            isAdopted: isAdopted
        )
        requiresInitialBootstrap = !isAdopted
    }

    @discardableResult
    private func stopManagedInitialOccurrence(
        _ owner: ManagedInitialOccurrence,
        viewsHandler: RUMViewsHandler?
    ) -> [RUMViewTrackingState.Transition] {
        var stoppedIdentities: Set<String> = []
        return stopManagedInitialOccurrence(
            owner,
            viewsHandler: viewsHandler,
            stoppedIdentities: &stoppedIdentities
        )
    }

    private func stopManagedInitialOccurrence(
        _ owner: ManagedInitialOccurrence,
        viewsHandler: RUMViewsHandler?,
        stoppedIdentities: inout Set<String>
    ) -> [RUMViewTrackingState.Transition] {
        stopNavigationOwnedOccurrence(
            state: owner.state,
            configuration: owner.state.configuration ?? owner.configuration,
            sceneIdentifier: owner.sceneIdentifier,
            viewsHandler: viewsHandler,
            stoppedIdentities: &stoppedIdentities
        )
    }

    private func stopNavigationOwnedOccurrence(
        state: RUMViewTrackingState,
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        viewsHandler: RUMViewsHandler?,
        stoppedIdentities: inout Set<String>
    ) -> [RUMViewTrackingState.Transition] {
        _ = state.settleRetainedRouteHandoff(
            configuration: configuration,
            sceneIdentifier: sceneIdentifier
        )
        let transitions = state.disappear(configuration: configuration).filter { transition in
            guard case .stop(let identity, _) = transition else {
                return true
            }
            return stoppedIdentities.insert(identity).inserted
        }
        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: state,
            fallback: configuration.descriptor,
            to: viewsHandler
        )
        return transitions
    }

    private func consumePendingRevealedRoute(
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        into state: RUMViewTrackingState,
        viewsHandler: RUMViewsHandler?
    ) -> CandidateDisposition? {
        guard let pendingRevealedRoute else {
            return nil
        }
        if pendingRevealedRoute.state.needsReaderRemount {
            self.pendingRevealedRoute = nil
            return .allowOrdinaryMount
        }
        guard pendingRevealedRoute.configuration == configuration else {
            if configuration.bindingGeneration
                > pendingRevealedRoute.configuration.bindingGeneration {
                clearPendingRevealedRoute()
            }
            return nil
        }

        guard pendingRevealedRoute.sceneIdentifier == sceneIdentifier else {
            let reusesPendingState = pendingRevealedRoute.state === state
            _ = pendingRevealedRoute.state.settleRetainedRouteHandoff(
                configuration: pendingRevealedRoute.configuration,
                sceneIdentifier: pendingRevealedRoute.sceneIdentifier
            )
            let transitions = pendingRevealedRoute.state.disappear(
                configuration: pendingRevealedRoute.configuration
            )
            RUMSwiftUIViewTransitionPublisher.publish(
                transitions,
                state: pendingRevealedRoute.state,
                fallback: pendingRevealedRoute.configuration.descriptor,
                to: viewsHandler
            )
            self.pendingRevealedRoute = nil
            if reusesPendingState {
                let transitions = state.remountSourceManagedNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
                RUMSwiftUIViewTransitionPublisher.publish(
                    transitions,
                    state: state,
                    fallback: configuration.descriptor,
                    to: viewsHandler
                )
                return state.activeLifecycleGeneration == nil
                    ? .rejectStale
                    : .handled
            }
            return .allowOrdinaryMount
        }

        if pendingRevealedRoute.state === state {
            _ = state.settleRetainedRouteHandoff(
                configuration: configuration,
                sceneIdentifier: sceneIdentifier
            )
            self.pendingRevealedRoute = nil
            return .handled
        }

        guard pendingRevealedRoute.state.transferRetainedRouteOccurrence(
            to: state,
            configuration: configuration,
            sceneIdentifier: sceneIdentifier
        ) else {
            return .rejectStale
        }
        self.pendingRevealedRoute = nil
        return .handled
    }

    private func clearPendingRevealedRoute() {
        guard let pendingRevealedRoute else {
            return
        }
        _ = pendingRevealedRoute.state.settleRetainedRouteHandoff(
            configuration: pendingRevealedRoute.configuration,
            sceneIdentifier: pendingRevealedRoute.sceneIdentifier
        )
        self.pendingRevealedRoute = nil
    }
}

/// Retained route callbacks must not capture a modifier or its State storage.
/// The registration owns this context; its collaborators have independent lives.
@MainActor
internal final class RUMSwiftUINavigationOccurrenceContext {
    private weak var state: RUMViewTrackingState?
    private weak var viewsHandler: RUMViewsHandler?
    private let fallback: RUMViewTrackingState.Configuration.Descriptor
    #if os(iOS)
    weak var transitionArbiter: RUMSwiftUIInteractiveTransitionArbiter?
    #endif

    init(
        state: RUMViewTrackingState,
        viewsHandler: RUMViewsHandler?,
        fallback: RUMViewTrackingState.Configuration.Descriptor
    ) {
        self.state = state
        self.viewsHandler = viewsHandler
        self.fallback = fallback
    }

    func process(configuration: RUMViewTrackingState.Configuration, sceneIdentifier: RUMSceneIdentifier) {
        guard let state else {
            return
        }
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(
                .reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                ),
                state: state,
                send: publish
            )
            return
        }
        #endif
        publish(
            state.reconcile(
                configuration: configuration,
                attachment: .attached(sceneIdentifier),
                isAppeared: true
            )
        )
    }

    private func publish(_ transitions: [RUMViewTrackingState.Transition]) {
        guard let state else {
            return
        }
        RUMSwiftUIViewTransitionPublisher.publish(transitions, state: state, fallback: fallback, to: viewsHandler)
    }
}

/// Stable state retained by one keyed modifier while its hidden scene reader
/// callbacks are rebound to newer SwiftUI values.
@MainActor
internal final class RUMSwiftUINavigationOccurrenceRegistration {
    typealias Process = (
        RUMViewTrackingState.Configuration,
        RUMSceneIdentifier
    ) -> Void

    private weak var source: RUMSwiftUINavigationOccurrenceSource?
    private weak var state: RUMViewTrackingState?
    private var configuration: RUMViewTrackingState.Configuration?
    private var attachment: RUMViewTrackingState.Attachment = .detached
    private var process: Process?
    private(set) var callbackEpoch: UInt64 = 0

    fileprivate var trackingState: RUMViewTrackingState? {
        state
    }

    fileprivate var descriptor: RUMViewTrackingState.Configuration.Descriptor? {
        configuration?.descriptor
    }

    func rebind(
        to source: RUMSwiftUINavigationOccurrenceSource,
        state: RUMViewTrackingState,
        configuration: RUMViewTrackingState.Configuration,
        attachment: RUMViewTrackingState.Attachment,
        process: @escaping Process
    ) {
        cancel()
        self.source = source
        self.state = state
        self.configuration = configuration
        self.attachment = attachment
        self.process = process
        source.register(self, callbackEpoch: callbackEpoch)
    }

    /// Retained, hidden routes stay registered. Cancel only when replacing or
    /// removing the binding; final owner destruction releases the callback.
    func cancel() {
        callbackEpoch &+= 1
        source?.unregister(self)
        source = nil
        state = nil
        configuration = nil
        attachment = .detached
        process = nil
    }

    fileprivate func revealRetainedRoute(
        from source: RUMSwiftUINavigationOccurrenceSource,
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        expectedCallbackEpoch: UInt64
    ) -> RUMSceneIdentifier? {
        guard
            self.source === source,
            callbackEpoch == expectedCallbackEpoch,
            let state,
            let configuration,
            configuration.occurrenceKey == occurrenceKey,
            bindingGeneration > configuration.bindingGeneration,
            bindingGeneration > (state.configuration?.bindingGeneration ?? 0),
            state.lifecycleGeneration > 0 || !configuration.isCurrentDestination,
            !state.isAppeared,
            state.activeLifecycleGeneration == nil,
            !state.needsReaderRemount,
            state.attachment == attachment,
            let sceneIdentifier = state.retainedRouteSceneIdentifier,
            let process
        else {
            return nil
        }

        let nextConfiguration = RUMViewTrackingState.Configuration(
            occurrenceKey: occurrenceKey,
            bindingGeneration: bindingGeneration,
            descriptor: configuration.descriptor,
            isCurrentDestination: true
        )
        process(nextConfiguration, sceneIdentifier)
        return sceneIdentifier
    }
}
#endif

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
        case keyedInitialMount(
            configuration: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier
        )
        case keyedMount(
            configuration: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier
        )
        case promoteDormantBoundary(
            expected: RUMViewTrackingState.Configuration,
            accepted: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier
        )
        case migrateDormantBoundary(
            expected: RUMViewTrackingState.Configuration,
            accepted: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier
        )
        case settleDormantBoundary(
            expected: RUMViewTrackingState.Configuration,
            accepted: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier
        )
        case appear
        case disappear
        case reconcile(
            configuration: RUMViewTrackingState.Configuration,
            attachment: RUMViewTrackingState.Attachment?,
            isAppeared: Bool?
        )

        fileprivate var configuration: RUMViewTrackingState.Configuration? {
            switch self {
            case .keyedInitialMount(let configuration, _),
                 .keyedMount(let configuration, _),
                 .promoteDormantBoundary(_, let configuration, _),
                 .migrateDormantBoundary(_, let configuration, _),
                 .settleDormantBoundary(_, let configuration, _),
                 .reconcile(let configuration, _, _):
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
            case .keyedInitialMount(_, let sceneIdentifier),
                 .keyedMount(_, let sceneIdentifier),
                 .promoteDormantBoundary(_, _, let sceneIdentifier),
                 .migrateDormantBoundary(_, _, let sceneIdentifier):
                return .attached(sceneIdentifier)
            case .settleDormantBoundary:
                return .detached
            case .appear, .disappear:
                return nil
            case .reconcile(_, let attachment, _):
                return attachment
            }
        }

        fileprivate var isAppeared: Bool? {
            switch self {
            case .initialMount, .mount, .keyedInitialMount, .keyedMount,
                 .promoteDormantBoundary, .migrateDormantBoundary, .appear:
                return true
            case .settleDormantBoundary:
                return false
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
            case .keyedInitialMount(_, let sceneIdentifier),
                 .keyedMount(_, let sceneIdentifier),
                 .promoteDormantBoundary(_, _, let sceneIdentifier),
                 .migrateDormantBoundary(_, _, let sceneIdentifier),
                 .settleDormantBoundary(_, _, let sceneIdentifier):
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
            case .keyedInitialMount(let configuration, let sceneIdentifier):
                return state.mountFromInitialTrait(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            case .keyedMount(let configuration, let sceneIdentifier):
                return state.mountFromReader(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            case .promoteDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ):
                return state.promoteDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier
                )
            case .migrateDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ):
                return state.promoteDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier,
                    allowsSceneMigration: true
                )
            case .settleDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ):
                state.settleDormantNavigationPromotion(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier,
                    attachment: .detached,
                    isAppeared: false
                )
                return []
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
        weak var navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?

        init(
            observer: RUMSceneIdentifierReader.ObserverView,
            state: RUMViewTrackingState,
            navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
        ) {
            self.observer = observer
            self.state = state
            self.navigationOccurrenceSource = navigationOccurrenceSource
        }
    }

    private struct DormantBoundaryResolution: Equatable {
        let expected: RUMViewTrackingState.Configuration
        let accepted: RUMViewTrackingState.Configuration
        let sceneIdentifier: RUMSceneIdentifier
        let startsOccurrence: Bool
        let allowsSceneMigration: Bool
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
        var dormantBoundaryResolution: DormantBoundaryResolution?

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
            let requestedResolution: DormantBoundaryResolution?
            switch intent {
            case .promoteDormantBoundary(let expected, let accepted, let sceneIdentifier):
                requestedResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: true,
                    allowsSceneMigration: false
                )
            case .migrateDormantBoundary(let expected, let accepted, let sceneIdentifier):
                requestedResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: true,
                    allowsSceneMigration: true
                )
            case .settleDormantBoundary(let expected, let accepted, let sceneIdentifier):
                requestedResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: false,
                    allowsSceneMigration: false
                )
            default:
                requestedResolution = nil
            }

            if let requestedResolution {
                let canResolve = requestedResolution.startsOccurrence
                    ? state.canPromoteDormantNavigationBoundary(
                        from: requestedResolution.expected,
                        to: requestedResolution.accepted,
                        in: requestedResolution.sceneIdentifier,
                        allowsSceneMigration: requestedResolution.allowsSceneMigration
                    )
                    : state.canSettleDormantNavigationBoundary(
                        from: requestedResolution.expected,
                        to: requestedResolution.accepted,
                        in: requestedResolution.sceneIdentifier
                    )
                guard canResolve else {
                    return false
                }

                if
                    dormantBoundaryResolution != requestedResolution
                        || baseRevision != state.revision {
                    // Dormant reader bookkeeping can advance synchronously
                    // while an interactive transition is pending. Only this
                    // exact source-authorized resolution may rebase the
                    // projection onto that newer live snapshot.
                    baseRevision = state.revision
                    dormantBoundaryResolution = nil
                    configuration = state.configuration
                    attachment = nil
                    isAppeared = nil
                    allowsRemount = false
                    containsReaderMount = false
                }
            } else if let dormantBoundaryResolution,
                      !dormantBoundaryResolution.startsOccurrence {
                // A source-authorized detached settlement stays non-starting.
                // Only a later concrete reader resolution may upgrade it.
                return false
            } else if
                let dormantBoundaryResolution,
                let incomingConfiguration = intent.configuration,
                incomingConfiguration != dormantBoundaryResolution.accepted {
                // Generation orders callbacks but does not prove that a
                // destination was accepted by the customer's router. A generic
                // callback must not replace a source-authorized resolution.
                return false
            }
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
            } else if case .keyedInitialMount(_, let sceneIdentifier) = intent {
                attachment = .attached(sceneIdentifier)
                isAppeared = true
            } else if case .mount(let sceneIdentifier) = intent {
                attachment = .attached(sceneIdentifier)
                isAppeared = state.appearanceForReaderMount
                allowsRemount = true
                containsReaderMount = true
            } else if case .keyedMount(_, let sceneIdentifier) = intent {
                attachment = .attached(sceneIdentifier)
                isAppeared = state.appearanceForReaderMount
                allowsRemount = true
                containsReaderMount = true
            } else if case .promoteDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                dormantBoundaryResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: true,
                    allowsSceneMigration: false
                )
                attachment = .attached(sceneIdentifier)
                isAppeared = true
            } else if case .migrateDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                dormantBoundaryResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: true,
                    allowsSceneMigration: true
                )
                attachment = .attached(sceneIdentifier)
                isAppeared = true
            } else if case .settleDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                dormantBoundaryResolution = DormantBoundaryResolution(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier,
                    startsOccurrence: false,
                    allowsSceneMigration: false
                )
                attachment = .detached
                isAppeared = false
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
            if case .keyedInitialMount = intent, !state.acceptsInitialTraitMount {
                return false
            }
            if case .mount = intent, !state.acceptsReaderMount {
                return false
            }
            if case .keyedMount = intent, !state.acceptsReaderMount {
                return false
            }
            if case .promoteDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                guard state.canPromoteDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier
                ) else {
                    return false
                }
                guard dormantBoundaryResolution == nil else {
                    return true
                }
                return configuration == state.configuration
            }
            if case .migrateDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                guard state.canPromoteDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier,
                    allowsSceneMigration: true
                ) else {
                    return false
                }
                guard dormantBoundaryResolution == nil else {
                    return true
                }
                return configuration == state.configuration
            }
            if case .settleDormantBoundary(
                let expected,
                let accepted,
                let sceneIdentifier
            ) = intent {
                guard state.canSettleDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier
                ) else {
                    return false
                }
                guard dormantBoundaryResolution == nil else {
                    return true
                }
                return configuration == state.configuration
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

        func preserveDormantPromotionAfterSceneDisconnect() {
            guard let dormantBoundaryResolution else {
                return
            }
            _ = state.preserveDormantNavigationPromotionAfterSceneDisconnect(
                from: dormantBoundaryResolution.expected,
                to: dormantBoundaryResolution.accepted
            )
        }

        var needsReaderRemountRearm: Bool {
            containsReaderMount && state.needsReaderRemount
        }

        func commit() {
            let transitions: [RUMViewTrackingState.Transition]
            if
                let dormantBoundaryResolution,
                dormantBoundaryResolution.startsOccurrence,
                configuration == dormantBoundaryResolution.accepted,
                attachment == .attached(dormantBoundaryResolution.sceneIdentifier),
                isAppeared != false {
                transitions = state.promoteDormantNavigationBoundary(
                    from: dormantBoundaryResolution.expected,
                    to: dormantBoundaryResolution.accepted,
                    in: dormantBoundaryResolution.sceneIdentifier,
                    expectedRevision: baseRevision,
                    allowsSceneMigration: dormantBoundaryResolution.allowsSceneMigration
                )
            } else if let dormantBoundaryResolution {
                state.settleDormantNavigationPromotion(
                    from: dormantBoundaryResolution.expected,
                    to: dormantBoundaryResolution.accepted,
                    in: dormantBoundaryResolution.sceneIdentifier,
                    attachment: attachment,
                    isAppeared: isAppeared,
                    expectedRevision: baseRevision
                )
                transitions = []
            } else if let configuration {
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

        func preserveDormantPromotionsAfterSceneDisconnect(
            statesWithIdentities identities: Set<ObjectIdentifier>
        ) {
            states.forEach { identity, state in
                if identities.contains(identity) {
                    state.preserveDormantPromotionAfterSceneDisconnect()
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
        for state: RUMViewTrackingState,
        navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource? = nil
    ) {
        guard Thread.isMainThread else {
            return
        }
        observerRegistrations[ObjectIdentifier(observer)] = ObserverRegistration(
            observer: observer,
            state: state,
            navigationOccurrenceSource: navigationOccurrenceSource
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
        deferredTransitions.forEach { key, transition in
            guard key.sceneIdentifier == sceneIdentifier else {
                return
            }
            transition.preserveDormantPromotionsAfterSceneDisconnect(
                statesWithIdentities: invalidatedStateIdentities
            )
        }

        var disconnectedSources: [ObjectIdentifier: RUMSwiftUINavigationOccurrenceSource] = [:]
        observerRegistrations.values.forEach { registration in
            guard
                let source = registration.navigationOccurrenceSource,
                let state = registration.state,
                let observer = registration.observer,
                observer.lastSceneIdentifier == sceneIdentifier
                    || invalidatedStateIdentities.contains(ObjectIdentifier(state))
            else {
                return
            }
            disconnectedSources[ObjectIdentifier(source)] = source
        }
        disconnectedSources.values.forEach { source in
            Task { @MainActor [weak source] in
                source?.sceneDidDisconnect(sceneIdentifier)
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
        // Merge before removing the state from its original coordinator. A
        // generic callback from another scene may pass the broad projection
        // fence but still be rejected because a source-authorized settlement
        // is pending. In that case the original settlement must remain owned
        // by its coordinator.
        guard deferredState.merge(intent, send: send) else {
            return
        }
        guard pending.transition.remove(state: state) != nil else {
            return
        }
        if pending.transition.isEmpty {
            deferredTransitions.removeValue(forKey: pending.key)
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

    /// Navigation occurrence metadata used only by the internal experimental
    /// integration. Public tracking keeps this unset and follows the existing
    /// lifecycle path.
    #if os(iOS) || os(visionOS)
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
    #endif

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
                    attributes: attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: navigationOccurrenceSource
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
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?

    func body(content: Content) -> some View {
        if #available(iOS 17.0, visionOS 1.0, *) {
            content.modifier(
                RUMTraitBackedMultiSceneViewModifier(
                    instrumentation: instrumentation,
                    name: name,
                    path: path,
                    attributes: attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: navigationOccurrenceSource,
                    startsOnInitialMount: startsOnInitialMount
                )
            )
        } else {
            content.modifier(
                RUMAttachmentBackedMultiSceneViewModifier(
                    instrumentation: instrumentation,
                    name: name,
                    path: path,
                    attributes: attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: navigationOccurrenceSource
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
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
    let startsOnInitialMount: Bool

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    @State private var trackingState = RUMViewTrackingState()
    @State private var didReceiveInitialSceneIdentifier = false
    @State private var navigationOccurrenceRegistration =
        RUMSwiftUINavigationOccurrenceRegistration()

    func body(content: Content) -> some View {
        reconcileDormantNavigationBoundaryFromEnvironmentTrait()
        return content
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
                    onReconcile: configuration == nil ? nil : { attachment in
                        update(
                            attachment: attachment,
                            allowsDormantBoundaryPromotion: true
                        )
                        rebindNavigationOccurrenceSource(attachment: attachment)
                    },
                    onChange: { attachment in
                        update(attachment: attachment)
                        rebindNavigationOccurrenceSource(attachment: attachment)
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

    /// iOS 27 may reuse the speculative route's modifier state for the route
    /// accepted by a canonicalizing Binding. Reconcile during body evaluation so
    /// the accepted RUM view is queued before customer `onAppear` and immediate
    /// task work. The source and state retain the scene/generation fences; this
    /// trait-backed path cannot migrate or recover a disconnected boundary.
    private func reconcileDormantNavigationBoundaryFromEnvironmentTrait() {
        guard
            startsOnInitialMount,
            let configuration,
            let navigationOccurrenceSource,
            let sceneIdentifier = initialSceneIdentifier
        else {
            return
        }
        guard
            case .promoteDormantBoundary(let expected, let accepted) =
                navigationOccurrenceSource.resolveDormantCandidateFromEnvironmentTrait(
                    candidateConfiguration: configuration,
                    sceneIdentifier: sceneIdentifier,
                    state: trackingState
                )
        else {
            return
        }
        promoteDormantNavigationBoundary(
            from: expected,
            to: accepted,
            in: sceneIdentifier
        )
    }

    private var initialSceneIdentifier: RUMSceneIdentifier? {
        guard startsOnInitialMount else {
            return nil
        }
        return sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    private func register(observer: RUMSceneIdentifierReader.ObserverView) {
        #if os(iOS)
        transitionArbiter?.register(
            observer: observer,
            for: trackingState,
            navigationOccurrenceSource: navigationOccurrenceSource
        )
        instrumentation?.swiftUIViewAuthorityRegistry?.register(
            observer: observer,
            trackingState: trackingState
        )
        #endif
    }

    private func mount(in sceneIdentifier: RUMSceneIdentifier) {
        if let configuration {
            switch resolveNavigationCandidate(
                configuration,
                in: sceneIdentifier,
                isReaderMount: true,
                allowsDormantBoundaryPromotion: true
            ) {
            case .handled:
                rebindNavigationOccurrenceSource(attachment: .attached(sceneIdentifier))
                return
            case .rejectStale:
                return
            case .recordDormant:
                let attachment = RUMViewTrackingState.Attachment.attached(sceneIdentifier)
                if recordDormantNavigationBoundaryFromReaderMount(
                    attachment: attachment
                ) {
                    rebindNavigationOccurrenceSource(attachment: attachment)
                    return
                }
                update(attachment: attachment)
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            case .promoteDormantBoundary(let expected, let accepted):
                promoteDormantNavigationBoundary(
                    from: expected,
                    to: accepted,
                    in: sceneIdentifier
                )
                return
            case .allowOrdinaryMount:
                break
            }
            if trackingState.needsReaderRemount {
                apply(
                    trackingState.mountCurrentNavigationDestinationAfterSceneDisconnect(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
                if trackingState.activeLifecycleGeneration != nil {
                    rebindNavigationOccurrenceSource(
                        attachment: .attached(sceneIdentifier)
                    )
                    return
                }
            }
            guard configuration.isCurrentDestination else {
                let attachment = RUMViewTrackingState.Attachment.attached(sceneIdentifier)
                update(attachment: attachment)
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            }
            #if os(iOS)
            if let transitionArbiter {
                transitionArbiter.process(
                    .keyedMount(
                        configuration: configuration,
                        sceneIdentifier: sceneIdentifier
                    ),
                    state: trackingState,
                    send: apply
                )
                return
            }
            #endif
            apply(
                trackingState.mountFromReader(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            )
            return
        }
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.mount(sceneIdentifier), state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.mountFromReader(in: sceneIdentifier))
    }

    private func initialMount(in sceneIdentifier: RUMSceneIdentifier) {
        if let configuration {
            switch resolveNavigationCandidate(configuration, in: sceneIdentifier) {
            case .handled:
                rebindNavigationOccurrenceSource(attachment: .attached(sceneIdentifier))
                return
            case .rejectStale:
                return
            case .recordDormant:
                let attachment = RUMViewTrackingState.Attachment.attached(sceneIdentifier)
                if trackingState.recordDormantNavigationBoundary(
                    configuration: configuration,
                    attachment: attachment
                ) {
                    rebindNavigationOccurrenceSource(attachment: attachment)
                    return
                }
                update(attachment: attachment)
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            case .promoteDormantBoundary:
                return
            case .allowOrdinaryMount:
                break
            }
            guard configuration.isCurrentDestination else {
                let attachment = RUMViewTrackingState.Attachment.attached(sceneIdentifier)
                update(attachment: attachment)
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            }
            #if os(iOS)
            if let transitionArbiter {
                transitionArbiter.process(
                    .keyedInitialMount(
                        configuration: configuration,
                        sceneIdentifier: sceneIdentifier
                    ),
                    state: trackingState,
                    send: apply
                )
                return
            }
            #endif
            apply(
                trackingState.mountFromInitialTrait(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            )
            return
        }
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

    private func update(
        attachment: RUMViewTrackingState.Attachment,
        allowsDormantBoundaryPromotion: Bool = false
    ) {
        if let configuration {
            if navigationOccurrenceSource?.retainsManagedInitialOccurrence(
                for: configuration,
                state: trackingState,
                attachment: attachment
            ) == true {
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            }
            if
                case .detached = attachment,
                allowsDormantBoundaryPromotion,
                navigationOccurrenceSource?.isAcceptedBoundary(configuration) == true,
                let sceneIdentifier = trackingState.retainedRouteSceneIdentifier,
                let dormantConfiguration = trackingState.configuration,
                trackingState.canSettleDormantNavigationBoundary(
                    from: dormantConfiguration,
                    to: configuration,
                    in: sceneIdentifier
                ) {
                settleDormantNavigationBoundary(
                    from: dormantConfiguration,
                    to: configuration,
                    in: sceneIdentifier
                )
                return
            }
            if case .attached(let sceneIdentifier?) = attachment {
                switch resolveNavigationCandidate(
                    configuration,
                    in: sceneIdentifier,
                    allowsDormantBoundaryPromotion: allowsDormantBoundaryPromotion
                ) {
                case .handled:
                    return
                case .rejectStale:
                    return
                case .recordDormant:
                    if trackingState.recordDormantNavigationBoundary(
                        configuration: configuration,
                        attachment: attachment
                    ) {
                        return
                    }
                case .promoteDormantBoundary(let expected, let accepted):
                    promoteDormantNavigationBoundary(
                        from: expected,
                        to: accepted,
                        in: sceneIdentifier
                    )
                    return
                case .allowOrdinaryMount:
                    break
                }
            }
            #if os(iOS)
            if let transitionArbiter {
                transitionArbiter.process(
                    .reconcile(
                        configuration: configuration,
                        attachment: attachment,
                        isAppeared: nil
                    ),
                    state: trackingState,
                    send: apply
                )
                return
            }
            #endif
            apply(trackingState.update(configuration: configuration, attachment: attachment))
            return
        }
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.update(attachment), state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.update(attachment: attachment))
    }

    private func appear() {
        if let configuration {
            if let sceneIdentifier = trackingState.sceneIdentifier {
                switch resolveNavigationCandidate(configuration, in: sceneIdentifier) {
                case .handled:
                    rebindNavigationOccurrenceSource(attachment: .attached(sceneIdentifier))
                    return
                case .rejectStale:
                    return
                case .recordDormant:
                    return
                case .promoteDormantBoundary:
                    return
                case .allowOrdinaryMount:
                    break
                }
            } else if navigationOccurrenceSource?.isAcceptedBoundary(configuration) == false {
                return
            }
            guard configuration.isCurrentDestination else {
                return
            }
            #if os(iOS)
            if let transitionArbiter {
                transitionArbiter.process(
                    .reconcile(
                        configuration: configuration,
                        attachment: nil,
                        isAppeared: true
                    ),
                    state: trackingState,
                    send: apply
                )
                return
            }
            #endif
            apply(trackingState.appear(configuration: configuration))
            return
        }
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.appear, state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.appear())
    }

    private func disappear() {
        if let configuration {
            if navigationOccurrenceSource?.retainsManagedInitialOccurrence(
                for: configuration,
                state: trackingState
            ) == true {
                return
            }
            #if os(iOS)
            if let transitionArbiter {
                transitionArbiter.process(
                    .reconcile(
                        configuration: configuration,
                        attachment: nil,
                        isAppeared: false
                    ),
                    state: trackingState,
                    send: apply
                )
                return
            }
            #endif
            apply(trackingState.disappear(configuration: configuration))
            return
        }
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(.disappear, state: trackingState, send: apply)
            return
        }
        #endif
        apply(trackingState.disappear())
    }

    private func rebindNavigationOccurrenceSource(
        attachment: RUMViewTrackingState.Attachment
    ) {
        guard let configuration, let navigationOccurrenceSource else {
            navigationOccurrenceRegistration.cancel()
            return
        }
        let context = RUMSwiftUINavigationOccurrenceContext(
            state: trackingState,
            viewsHandler: instrumentation?.viewsHandler,
            fallback: configuration.descriptor
        )
        #if os(iOS)
        context.transitionArbiter = transitionArbiter
        #endif
        navigationOccurrenceRegistration.rebind(
            to: navigationOccurrenceSource,
            state: trackingState,
            configuration: configuration,
            attachment: attachment,
            process: context.process
        )
    }

    private func resolveNavigationCandidate(
        _ configuration: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        isReaderMount: Bool = false,
        allowsDormantBoundaryPromotion: Bool = false
    ) -> RUMSwiftUINavigationOccurrenceSource.CandidateDisposition {
        guard let navigationOccurrenceSource else {
            return .allowOrdinaryMount
        }
        return navigationOccurrenceSource.resolveCandidate(
            candidateConfiguration: configuration,
            sceneIdentifier: sceneIdentifier,
            state: trackingState,
            isReaderMount: isReaderMount,
            allowsDormantBoundaryPromotion: allowsDormantBoundaryPromotion,
            viewsHandler: instrumentation?.viewsHandler
        ) { initialConfiguration, sceneIdentifier in
            apply(
                trackingState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: initialConfiguration
                )
            )
        }
    }

    private func promoteDormantNavigationBoundary(
        from expected: RUMViewTrackingState.Configuration,
        to accepted: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) {
        let requiresReaderAuthorization = !trackingState.canPromoteDormantNavigationBoundary(
            from: expected,
            to: accepted,
            in: sceneIdentifier
        )
        #if os(iOS)
        if let transitionArbiter {
            let intent: RUMSwiftUIInteractiveTransitionArbiter.Intent = requiresReaderAuthorization
                ? .migrateDormantBoundary(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier
                )
                : .promoteDormantBoundary(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier
                )
            transitionArbiter.process(
                intent,
                state: trackingState,
                send: apply
            )
            return
        }
        #endif
        apply(
            trackingState.promoteDormantNavigationBoundary(
                from: expected,
                to: accepted,
                in: sceneIdentifier,
                allowsSceneMigration: requiresReaderAuthorization
            )
        )
    }

    private func settleDormantNavigationBoundary(
        from expected: RUMViewTrackingState.Configuration,
        to accepted: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) {
        #if os(iOS)
        if let transitionArbiter {
            transitionArbiter.process(
                .settleDormantBoundary(
                    expected: expected,
                    accepted: accepted,
                    sceneIdentifier: sceneIdentifier
                ),
                state: trackingState,
                send: apply
            )
            return
        }
        #endif
        trackingState.settleDormantNavigationPromotion(
            from: expected,
            to: accepted,
            in: sceneIdentifier,
            attachment: .detached,
            isAppeared: false
        )
        apply([])
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
        navigationOccurrenceSource?.reconcileOwnerState(trackingState)
    }

    private func recordDormantNavigationBoundaryFromReaderMount(
        attachment: RUMViewTrackingState.Attachment
    ) -> Bool {
        guard let configuration else {
            return false
        }
        return trackingState.recordDormantNavigationBoundary(
            configuration: configuration,
            attachment: attachment
        ) || trackingState.rearmDormantNavigationBoundaryAfterSceneDisconnect(
            configuration: configuration,
            attachment: attachment
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
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?

    @State private var trackingState = RUMViewTrackingState()
    @State private var navigationOccurrenceRegistration =
        RUMSwiftUINavigationOccurrenceRegistration()

    func body(content: Content) -> some View {
        content
            .background(
                RUMSceneIdentifierReader(
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        register(observer: observer)
                    },
                    onReconcile: configuration == nil ? nil : { attachment in
                        update(attachment: attachment)
                        rebindNavigationOccurrenceSource(attachment: attachment)
                    },
                    onChange: { attachment in
                        update(attachment: attachment)
                        rebindNavigationOccurrenceSource(attachment: attachment)
                    }
                )
            )
            .onAppear {
                if let configuration {
                    apply(trackingState.appear(configuration: configuration))
                } else {
                    apply(trackingState.appear())
                }
            }
            .onDisappear {
                if let configuration {
                    apply(trackingState.disappear(configuration: configuration))
                } else {
                    apply(trackingState.disappear())
                }
            }
    }

    private func register(observer: RUMSceneIdentifierReader.ObserverView) {
        #if os(iOS)
        instrumentation?.swiftUIViewAuthorityRegistry?.register(
            observer: observer,
            trackingState: trackingState
        )
        #endif
    }

    private func update(attachment: RUMViewTrackingState.Attachment) {
        if let configuration {
            if
                case .attached(let sceneIdentifier?) = attachment,
                consumeRevealedRoute(configuration, in: sceneIdentifier) {
                return
            }
            apply(trackingState.update(configuration: configuration, attachment: attachment))
        } else {
            apply(trackingState.update(attachment: attachment))
        }
    }

    private func rebindNavigationOccurrenceSource(
        attachment: RUMViewTrackingState.Attachment
    ) {
        guard let configuration, let navigationOccurrenceSource else {
            navigationOccurrenceRegistration.cancel()
            return
        }
        let context = RUMSwiftUINavigationOccurrenceContext(
            state: trackingState,
            viewsHandler: instrumentation?.viewsHandler,
            fallback: configuration.descriptor
        )
        navigationOccurrenceRegistration.rebind(
            to: navigationOccurrenceSource,
            state: trackingState,
            configuration: configuration,
            attachment: attachment,
            process: context.process
        )
    }

    private func consumeRevealedRoute(
        _ configuration: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        navigationOccurrenceSource?.consumeRevealedRoute(
            configuration: configuration,
            sceneIdentifier: sceneIdentifier,
            into: trackingState
        ) == true
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

#if os(iOS)
/// Presentation half of semantic navigation ownership. The router publishes
/// the RUM occurrence, while this modifier keeps automatic discovery out of
/// the presented platform subtree until UIKit finishes removing it.
private struct RUMAutomaticViewSuppressionModifier: SwiftUI.ViewModifier {
    let instrumentation: RUMInstrumentation?

    @State private var suppressionState = RUMSwiftUIAutomaticViewSuppressionState()

    func body(content: Content) -> some View {
        content
            .background(
                RUMSceneIdentifierReader(
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        instrumentation?.swiftUIViewAuthorityRegistry?.register(
                            observer: observer,
                            suppressionState: suppressionState
                        )
                    },
                    onChange: { _ in }
                )
            )
            .onAppear {
                suppressionState.appear()
            }
            .onDisappear {
                suppressionState.disappear()
            }
    }
}
#endif

#if os(iOS)
/// The native presentation style associated with a semantic RUM destination.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
public enum RUMNavigationPresentationStyle: Hashable {
    case sheet
    case fullScreenCover
}

/// Describes one presented destination in an experimental semantic navigation
/// container.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
public struct RUMNavigationPresentation {
    public let view: RUMView
    public let style: RUMNavigationPresentationStyle

    public init(view: RUMView, style: RUMNavigationPresentationStyle) {
        self.view = view
        self.style = style
    }
}

/// A stable, type-erased source of committed navigation destinations.
///
/// Keep one instance for the lifetime of an independent navigation container.
/// Preparing a transition does not change RUM state. Committing it creates a
/// fresh RUM view occurrence, even when its destination metadata matches an
/// earlier occurrence. Cancelling it leaves the current occurrence unchanged.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
public final class RUMNavigationTransitions {
    internal struct Snapshot {
        let generation: UInt64
        let destination: RUMView
    }

    private var nextGeneration: UInt64 = 0
    private var currentSnapshot: Snapshot?
    private var preparedDestinations: [String: RUMView] = [:]
    private var observers: [UUID: (Snapshot) -> Void] = [:]

    public init() {}

    public convenience init(currentDestination: RUMView) {
        self.init()
        setInitialDestination(currentDestination)
    }

    /// Publishes the container's initial committed destination exactly once.
    /// This allows a stable source to be created before scene-dependent RUM
    /// metadata is available.
    public func setInitialDestination(_ destination: RUMView) {
        guard currentSnapshot == nil else {
            return
        }
        let snapshot = Snapshot(
            generation: nextGeneration,
            destination: destination
        )
        currentSnapshot = snapshot
        observers.values.forEach { $0(snapshot) }
    }

    /// Records a possible destination without starting a RUM view.
    public func willNavigate(id: String, destination: RUMView) {
        preparedDestinations[id] = destination
    }

    /// Commits the prepared transition and publishes a fresh occurrence.
    public func commit(id: String) {
        guard let destination = preparedDestinations.removeValue(forKey: id) else {
            return
        }
        nextGeneration &+= 1
        let snapshot = Snapshot(
            generation: nextGeneration,
            destination: destination
        )
        currentSnapshot = snapshot
        observers.values.forEach { $0(snapshot) }
    }

    /// Cancels a prepared transition without changing the current occurrence.
    public func cancel(id: String) {
        preparedDestinations.removeValue(forKey: id)
    }

    @discardableResult
    internal func observe(_ observer: @escaping (Snapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        if let currentSnapshot {
            observer(currentSnapshot)
        }
        return id
    }

    internal func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}

/// One committed destination from an application-owned navigation state stream.
///
/// Its hashable value is retained only as an in-memory occurrence identity. RUM
/// metadata is derived from the value's type and enum case without serializing
/// associated values or invoking customer descriptions.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
public struct RUMNavigationDestination {
    internal enum Kind: String, Hashable {
        case root
        case route
        case presentation
    }

    internal struct Identity: Hashable {
        let kind: Kind
        let value: AnyHashable
        let occurrence: AnyHashable?
    }

    internal let identity: Identity
    internal let value: AnyHashable
    internal let kind: Kind
    internal let automaticKey: String
    internal let attributes: [String: Encodable]

    /// Describes the root currently visible in an independent container.
    public static func root<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(value: value, kind: .root, attributes: attributes)
    }

    /// Describes the last committed route currently visible in a container.
    public static func route<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(
            value: value,
            kind: .route,
            attributes: attributes,
            occurrence: nil
        )
    }

    /// Describes a route whose source can distinguish equal-value occurrences.
    ///
    /// The occurrence token is an application navigation identity retained only
    /// in memory. It is not a RUM view UUID and is never serialized. A path depth
    /// or coordinator-owned transition identity is sufficient when equal route
    /// values can occupy multiple positions.
    public static func route<Value: Hashable, Occurrence: Hashable>(
        _ value: Value,
        occurrence: Occurrence,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(
            value: value,
            kind: .route,
            attributes: attributes,
            occurrence: AnyHashable(occurrence)
        )
    }

    /// Describes the sheet or full-screen cover replacing the underlying route.
    public static func presentation<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(value: value, kind: .presentation, attributes: attributes)
    }

    private init<Value: Hashable>(
        value: Value,
        kind: Kind,
        attributes: [String: Encodable],
        occurrence: AnyHashable? = nil
    ) {
        let value = AnyHashable(value)
        self.identity = Identity(
            kind: kind,
            value: value,
            occurrence: occurrence
        )
        self.value = value
        self.kind = kind
        self.automaticKey = Self.automaticKey(for: value.base)
        self.attributes = attributes
    }

    private static func automaticKey(for value: Any) -> String {
        if case let .enum(caseName) = ReflectionMirror(reflecting: value).displayStyle,
           !caseName.isEmpty {
            return caseName
        }

        let reflectedType = String(reflecting: type(of: value))
        return reflectedType.split(separator: ".").last.map(String.init)
            ?? reflectedType
    }
}

/// Automatic metadata plus optional sparse overrides for semantic navigation.
///
/// Correct occurrence tracking never requires an override. Overrides only tune
/// business-facing names or paths for exceptional destinations.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
public struct RUMNavigationMetadata {
    internal struct Override {
        let name: String
        let path: String?
    }

    public static let automatic = Self()

    internal var namespace: String?
    internal var overrides: [AnyHashable: Override] = [:]

    public init() {}

    /// Creates automatic metadata beneath one stable container namespace.
    public static func automatic(in namespace: String) -> Self {
        var metadata = Self()
        metadata.namespace = namespace
        return metadata
    }

    /// Returns a copy with one optional business-facing metadata override.
    public func overriding<Value: Hashable>(
        _ value: Value,
        name: String,
        path: String? = nil
    ) -> Self {
        var copy = self
        copy.overrides[AnyHashable(value)] = Override(name: name, path: path)
        return copy
    }

    internal func view(for destination: RUMNavigationDestination) -> RUMView {
        let override = overrides[destination.value]
        var view = RUMView(
            name: override?.name ?? Self.humanized(destination.automaticKey),
            attributes: destination.attributes
        )
        view.path = override?.path ?? automaticPath(for: destination)
        return view
    }

    private func automaticPath(for destination: RUMNavigationDestination) -> String {
        var components: [String] = []
        if let namespace {
            components.append(Self.slug(namespace))
        }
        if destination.kind == .presentation {
            components.append("presentation")
        }

        let key = Self.slug(destination.automaticKey)
        if destination.kind != .root || components.last != key {
            components.append(key)
        }
        return "/" + components.filter { !$0.isEmpty }.joined(separator: "/")
    }

    private static func humanized(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isUppercase, !result.isEmpty {
                result.append(" ")
            }
            result.append(character == "_" ? " " : character)
        }
        return result.capitalized
    }

    private static func slug(_ value: String) -> String {
        let slug = humanized(value)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
        return String(slug).split(separator: "-").joined(separator: "-")
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
internal final class RUMNavigationObservedTransitions: ObservableObject {
    @Published private(set) var transitions: RUMNavigationTransitions?

    private var currentIdentity: RUMNavigationDestination.Identity?
    private var cancellable: AnyCancellable?
#if compiler(>=6.4)
    private var observedCurrentDestination:
        (@MainActor () -> RUMNavigationDestination)?
    private var observedCurrentDestinationMetadata: RUMNavigationMetadata?
#endif

    init() {
        transitions = nil
    }

    init<State, Updates: Publisher>(
        updates: Updates,
        destination: @MainActor @escaping (State) -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata
    ) where Updates.Output == State, Updates.Failure == Never {
        transitions = nil
        cancellable = updates.sink { [weak self] state in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.receive(destination(state), metadata: metadata)
                }
            } else {
                // Combine serializes downstream delivery, and the main queue
                // preserves that submission order. This keeps an erroneous
                // background router crash-safe without allowing independent
                // unstructured tasks to reorder committed occurrences.
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.receive(destination(state), metadata: metadata)
                    }
                }
            }
        }
    }

#if compiler(>=6.4)
    /// Observes one atomically updated property on an iOS 27 `@Observable`
    /// router at its accepted-state boundary.
    ///
    /// One-shot `.didSet` delivery is synchronous after the new value is stored.
    /// Rearming from the callback preserves that ordering for the next mutation.
    /// The public host keeps Observation out of its signature by accepting only
    /// the destination projection closure.
    init(
        observingCurrentDestination: @MainActor @escaping () ->
            RUMNavigationDestination,
        metadata: RUMNavigationMetadata
    ) {
        transitions = nil
        observedCurrentDestination = observingCurrentDestination
        observedCurrentDestinationMetadata = metadata
        armCurrentDestinationObservation()
    }

    private func armCurrentDestinationObservation() {
        guard
            let observedCurrentDestination,
            let metadata = observedCurrentDestinationMetadata
        else {
            return
        }

        let destination = withObservationTracking(options: [.didSet]) {
            observedCurrentDestination()
        } onChange: { [weak self] event in
            guard event.kind == .didSet else {
                return
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.armCurrentDestinationObservation()
                }
            } else {
                // Navigation state is expected to be MainActor-owned. An invalid
                // background mutation must remain crash-safe; it may lose exact
                // intermediate timing, but rearms against the latest value.
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.armCurrentDestinationObservation()
                    }
                }
            }
        }
        receive(destination, metadata: metadata)
    }
#endif

    private func receive(
        _ destination: RUMNavigationDestination,
        metadata: RUMNavigationMetadata
    ) {
        guard destination.identity != currentIdentity else {
            return
        }
        currentIdentity = destination.identity

        let view = metadata.view(for: destination)
        guard let transitions else {
            self.transitions = RUMNavigationTransitions(
                currentDestination: view
            )
            return
        }
        let transitionID = UUID().uuidString
        transitions.willNavigate(id: transitionID, destination: view)
        transitions.commit(id: transitionID)
    }
}

/// Optional exact-navigation capability for a customer-owned container.
///
/// The returned source must remain stable while the container is reconstructed
/// as SwiftUI view values. Imported third-party containers should normally use
/// the explicit `RUMNavigationHost(transitions:content:)` initializer instead
/// of adding a retroactive conformance.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
public protocol RUMNavigationTransitionProviding {
    var rumNavigationTransitions: RUMNavigationTransitions { get }
}

/// Scene-scoped semantic navigation state independent of any visual container.
///
/// Native, custom, and coordinator adapters feed accepted destinations into this
/// engine. A SwiftUI host supplies only scene attachment and lifetime. Keeping
/// those roles separate lets an opaque customer container retain automatic view
/// tracking without inventing semantic transitions.
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
internal final class RUMSwiftUISemanticNavigationEngine {
    let occurrenceSource = RUMSwiftUINavigationOccurrenceSource()

    private(set) var attachment: RUMViewTrackingState.Attachment = .detached

    var sceneIdentifier: RUMSceneIdentifier? {
        guard case .attached(let sceneIdentifier) = attachment else {
            return nil
        }
        return sceneIdentifier
    }

    func reconcile(attachment: RUMViewTrackingState.Attachment) {
        self.attachment = attachment
    }

    func acceptDestination(
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        change: RUMSwiftUINavigationOccurrenceSource.DestinationChange
    ) {
        occurrenceSource.acceptDestination(
            occurrenceKey: occurrenceKey,
            bindingGeneration: bindingGeneration,
            change: change
        )
    }

    func reconcileCurrentDestination(
        configuration: RUMViewTrackingState.Configuration,
        viewsHandler: RUMViewsHandler?
    ) {
        occurrenceSource.reconcileCurrentDestination(
            configuration: configuration,
            viewsHandler: viewsHandler
        )
    }

    func cancelNavigationOwnedOccurrences(viewsHandler: RUMViewsHandler?) {
        occurrenceSource.cancelNavigationOwnedOccurrences(viewsHandler: viewsHandler)
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
internal final class RUMSemanticNavigationHostState {
    private struct ActiveOccurrence {
        let sourceGeneration: UInt64
        let identity: String
        let sceneIdentifier: RUMSceneIdentifier
    }

    let engine = RUMSwiftUISemanticNavigationEngine()
    let suppressionState = RUMSwiftUIAutomaticViewSuppressionState()

    private let hostID = UUID()
    private var attachmentGeneration: UInt64 = 0
    private var requiresReaderMount = false
    // A retained reader may mount before SwiftUI reevaluates the host body.
    // Remember its configuration without retaining a dormant subscription/source.
    private weak var configuredTransitions: RUMNavigationTransitions?
    private(set) var selectedTransitions: RUMNavigationTransitions?
    private var observationID: UUID?
    private var latestSnapshot: RUMNavigationTransitions.Snapshot?
    private var activeOccurrence: ActiveOccurrence?
    private weak var viewsHandler: RUMViewsHandler?

    func reconcile(
        transitions: RUMNavigationTransitions?,
        viewsHandler: RUMViewsHandler?
    ) {
        self.viewsHandler = viewsHandler
        if selectedTransitions == nil {
            configuredTransitions = transitions
        }

        guard let transitions else {
            return
        }
        guard selectedTransitions == nil else {
            // Pin the first source for this host identity. A computed capability
            // that creates a new source during every SwiftUI reconstruction must
            // not replay or disconnect the current RUM occurrence.
            activateLatestSnapshotIfPossible()
            return
        }

        selectedTransitions = transitions
        observationID = transitions.observe { [weak self] snapshot in
            self?.receive(snapshot)
        }
    }

    /// An inherited trait can bootstrap the first mount, but cannot prove a
    /// retained host has rejoined a scene after its previous lifetime ended.
    func reconcile(initialSceneIdentifier: RUMSceneIdentifier) {
        guard !requiresReaderMount else {
            return
        }
        reconcile(attachment: .attached(initialSceneIdentifier))
    }

    func reconcile(attachment: RUMViewTrackingState.Attachment) {
        if case .attached(let sceneIdentifier?) = attachment,
           viewsHandler?.canTrackViews(in: sceneIdentifier) == false {
            requiresReaderMount = true
            return
        }
        engine.reconcile(attachment: attachment)

        guard case .attached(let sceneIdentifier?) = attachment else {
            return
        }
        requiresReaderMount = false
        if
            let activeOccurrence,
            activeOccurrence.sceneIdentifier != sceneIdentifier {
            viewsHandler?.notify_semanticDestinationDisappear(
                identity: activeOccurrence.identity,
                sceneIdentifier: activeOccurrence.sceneIdentifier
            )
            self.activeOccurrence = nil
        }
        if selectedTransitions == nil {
            reconcile(transitions: configuredTransitions, viewsHandler: viewsHandler)
        }
        activateLatestSnapshotIfPossible()
    }

    func finalDetach() {
        if let activeOccurrence {
            viewsHandler?.notify_semanticDestinationDisappear(
                identity: activeOccurrence.identity,
                sceneIdentifier: activeOccurrence.sceneIdentifier
            )
        }
        releaseSource()
    }

    /// Releases a disconnected scene without publishing a second view stop.
    /// `RUMViewsHandler` owns the scene-disconnect stop and stack teardown.
    func sceneDidDisconnect(_ sceneIdentifier: RUMSceneIdentifier) {
        guard
            engine.sceneIdentifier == sceneIdentifier
                || activeOccurrence?.sceneIdentifier == sceneIdentifier
        else {
            return
        }
        engine.reconcile(attachment: .detached)
        releaseSource()
    }

    private func releaseSource() {
        attachmentGeneration &+= 1
        requiresReaderMount = true
        engine.reconcile(attachment: .detached)
        activeOccurrence = nil
        suppressionState.disappear()
        if let observationID {
            selectedTransitions?.removeObserver(observationID)
        }
        observationID = nil
        selectedTransitions = nil
        latestSnapshot = nil
    }

    private func receive(_ snapshot: RUMNavigationTransitions.Snapshot) {
        latestSnapshot = snapshot
        activateLatestSnapshotIfPossible()
    }

    private func activateLatestSnapshotIfPossible() {
        guard
            !requiresReaderMount,
            let latestSnapshot,
            let sceneIdentifier = engine.sceneIdentifier,
            let viewsHandler
        else {
            return
        }
        guard activeOccurrence?.sourceGeneration != latestSnapshot.generation else {
            return
        }

        let identity = "rum-navigation-host-\(hostID.uuidString)-\(attachmentGeneration)-\(latestSnapshot.generation)"
        let destination = latestSnapshot.destination
        let accepted: Bool
        if let activeOccurrence {
            accepted = viewsHandler.notify_semanticDestinationReplace(
                identity: activeOccurrence.identity,
                sceneIdentifier: activeOccurrence.sceneIdentifier,
                replacementIdentity: identity,
                replacementName: destination.name,
                replacementPath: destination.path ?? destination.name,
                replacementAttributes: destination.attributes,
                replacementSceneIdentifier: sceneIdentifier
            )
        } else {
            accepted = viewsHandler.notify_semanticDestinationAppear(
                identity: identity,
                name: destination.name,
                path: destination.path ?? destination.name,
                attributes: destination.attributes,
                sceneIdentifier: sceneIdentifier
            )
        }
        guard accepted else {
            return
        }
        activeOccurrence = ActiveOccurrence(
            sourceGeneration: latestSnapshot.generation,
            identity: identity,
            sceneIdentifier: sceneIdentifier
        )
        // Subscription alone has no authority over automatic tracking. Acquire
        // it only when a snapshot, scene and handler can establish an occurrence.
        suppressionState.appear()
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
internal final class RUMSwiftUISemanticNavigationState<
    Route: Hashable,
    Presentation: Identifiable
> {
    struct Occurrence {
        let key: RUMViewOccurrenceKey
        let generation: UInt64
        let isCurrentDestination: Bool
    }

    /// Stable control data retained by one materialized destination boundary.
    /// It preserves the path-position key while an equal route is hidden below
    /// another occurrence, without changing the customer's native `[Route]`.
    final class RouteOccurrenceClaim {
        fileprivate var route: Route
        fileprivate var key: RUMViewOccurrenceKey
        fileprivate var depth: Int

        fileprivate init(route: Route, key: RUMViewOccurrenceKey, depth: Int) {
            self.route = route
            self.key = key
            self.depth = depth
        }
    }

    private struct RootKey: Hashable {
        let containerID: UUID
    }

    private struct RoutePositionKey: Hashable {
        let containerID: UUID
        let route: Route
        let depth: Int
    }

    struct PresentationOccurrence: Hashable {
        fileprivate let identity: String
    }

    private struct ActivePresentation {
        var item: Presentation
        var descriptor: RUMNavigationPresentation
        let identity: String
        var sceneIdentifier: RUMSceneIdentifier?
        var isStarted: Bool
        var hasMounted: Bool
    }

    private let containerID = UUID()
    private(set) var bindingGeneration: UInt64 = 0
    private var currentPath: [Route]?
    private var activePresentation: ActivePresentation?
    private var outgoingPresentation: ActivePresentation?
    private var dismissedSheet: Presentation?
    private var dismissedFullScreenCover: Presentation?

    let engine: RUMSwiftUISemanticNavigationEngine

    var occurrenceSource: RUMSwiftUINavigationOccurrenceSource {
        engine.occurrenceSource
    }

    init() {
        self.engine = RUMSwiftUISemanticNavigationEngine()
    }

    init(engine: RUMSwiftUISemanticNavigationEngine) {
        self.engine = engine
    }

    var rootOccurrence: Occurrence {
        Occurrence(
            key: RUMViewOccurrenceKey(RootKey(containerID: containerID)),
            generation: bindingGeneration,
            isCurrentDestination: currentPath?.isEmpty ?? true
        )
    }

    func occurrence(for route: Route) -> Occurrence {
        let position = routePosition(for: route)
        return Occurrence(
            key: position.key,
            generation: bindingGeneration,
            isCurrentDestination: position.isCurrentDestination
        )
    }

    func makeOccurrenceClaim(for route: Route) -> RouteOccurrenceClaim {
        let position = routePosition(for: route)
        return RouteOccurrenceClaim(
            route: route,
            key: position.key,
            depth: position.depth
        )
    }

    func occurrence(
        for route: Route,
        retaining claim: RouteOccurrenceClaim
    ) -> Occurrence {
        let current = routePosition(for: route)
        if claim.route != route {
            claim.route = route
            claim.key = current.key
            claim.depth = current.depth
        } else if
            claim.depth > (currentPath?.count ?? 0),
            current.isCurrentDestination {
            // A restored stack can materialize only its top destination. If
            // equal values occupy multiple positions, that single boundary is
            // initially claimed at the deepest position. Rebase it when a pop
            // removes that position so the surviving destination becomes a
            // fresh RUM occurrence. Claims for positions still in the path are
            // retained, preserving normal equal-value push/pop ownership.
            claim.key = current.key
            claim.depth = current.depth
        }
        return Occurrence(
            key: claim.key,
            generation: bindingGeneration,
            isCurrentDestination: current.isCurrentDestination && claim.key == current.key
        )
    }

    private func routePosition(
        for route: Route
    ) -> (key: RUMViewOccurrenceKey, depth: Int, isCurrentDestination: Bool) {
        let path = currentPath ?? []
        let depth = path.lastIndex(of: route).map { $0 + 1 } ?? max(path.count, 1)
        return (
            key: RUMViewOccurrenceKey(
                RoutePositionKey(
                    containerID: containerID,
                    route: route,
                    depth: depth
                )
            ),
            depth: depth,
            isCurrentDestination: depth == path.count && path.last == route
        )
    }

    func reconcile(path: [Route]) {
        guard let previousPath = currentPath else {
            currentPath = path
            if !path.isEmpty {
                bindingGeneration &+= 1
            }
            let occurrence = path.last.map(occurrence(for:)) ?? rootOccurrence
            engine.acceptDestination(
                occurrenceKey: occurrence.key,
                bindingGeneration: occurrence.generation,
                change: .initial(requiresBootstrap: !path.isEmpty)
            )
            return
        }
        guard previousPath != path else {
            let occurrence = path.last.map(occurrence(for:)) ?? rootOccurrence
            engine.acceptDestination(
                occurrenceKey: occurrence.key,
                bindingGeneration: occurrence.generation,
                change: .unchanged
            )
            return
        }

        bindingGeneration &+= 1
        currentPath = path
        let occurrence = path.last.map(occurrence(for:)) ?? rootOccurrence
        let revealsRetainedDestination = path.count < previousPath.count
            && Array(previousPath.prefix(path.count)) == path
        engine.acceptDestination(
            occurrenceKey: occurrence.key,
            bindingGeneration: occurrence.generation,
            change: revealsRetainedDestination ? .retainedReveal : .replacement
        )
    }

    func reconcileCurrentDestination<Root: SwiftUI.View, Destination: SwiftUI.View>(
        root: RUMView,
        rootType: Root.Type,
        destination: (Route) -> RUMView,
        destinationType: Destination.Type,
        viewsHandler: RUMViewsHandler?
    ) {
        let currentOccurrence: Occurrence
        let rumView: RUMView
        let fallbackType: Any.Type
        if let route = currentPath?.last {
            currentOccurrence = occurrence(for: route)
            rumView = destination(route)
            fallbackType = destinationType
        } else {
            currentOccurrence = rootOccurrence
            rumView = root
            fallbackType = rootType
        }
        let path = rumView.path
            ?? "\(rumView.name)/\(String(describing: fallbackType).hashValue)"
        engine.reconcileCurrentDestination(
            configuration: RUMViewTrackingState.Configuration(
                occurrenceKey: currentOccurrence.key,
                bindingGeneration: currentOccurrence.generation,
                descriptor: .init(
                    name: rumView.name,
                    path: path,
                    attributes: rumView.attributes
                ),
                isCurrentDestination: true
            ),
            viewsHandler: viewsHandler
        )
    }

    func forward(
        proposedPath: [Route],
        to path: Binding<[Route]>,
        transaction: Transaction
    ) {
        path.transaction(transaction).wrappedValue = proposedPath
        reconcile(path: path.wrappedValue)
    }

    func presentationBinding(
        for style: RUMNavigationPresentationStyle,
        to presented: Binding<Presentation?>,
        descriptor: @escaping (Presentation) -> RUMNavigationPresentation,
        viewsHandler: @escaping () -> RUMViewsHandler?
    ) -> Binding<Presentation?> {
        Binding(
            get: {
                guard
                    let item = presented.wrappedValue,
                    self.presentationStyle(for: item) == style
                else {
                    return nil
                }
                return item
            },
            set: { newItem, transaction in
                if
                    newItem == nil,
                    let currentItem = presented.wrappedValue,
                    self.presentationStyle(for: currentItem) != style {
                    return
                }
                presented.transaction(transaction).wrappedValue = newItem
                self.reconcilePresentation(
                    presented.wrappedValue,
                    descriptor: descriptor,
                    viewsHandler: viewsHandler()
                )
            }
        )
    }

    func reconcilePresentation(
        _ item: Presentation?,
        descriptor: ((Presentation) -> RUMNavigationPresentation),
        viewsHandler: RUMViewsHandler?
    ) {
        guard let item else {
            finishActivePresentation(viewsHandler: viewsHandler, recordsDismissal: true)
            return
        }

        let nextDescriptor = descriptor(item)
        if
            var activePresentation,
            AnyHashable(activePresentation.item.id) == AnyHashable(item.id),
            activePresentation.descriptor.style == nextDescriptor.style {
            activePresentation.item = item
            activePresentation.descriptor = nextDescriptor
            self.activePresentation = activePresentation
            return
        }

        let mountedPresentation = activePresentation?.isStarted == true
            ? activePresentation
            : outgoingPresentation
        activePresentation = ActivePresentation(
            item: item,
            descriptor: nextDescriptor,
            identity: UUID().uuidString,
            sceneIdentifier: nil,
            isStarted: false,
            hasMounted: false
        )
        outgoingPresentation = mountedPresentation
    }

    func presentationStyle(for item: Presentation) -> RUMNavigationPresentationStyle? {
        guard
            let activePresentation,
            AnyHashable(activePresentation.item.id) == AnyHashable(item.id)
        else {
            return nil
        }
        return activePresentation.descriptor.style
    }

    func presentationOccurrence(
        for item: Presentation,
        style: RUMNavigationPresentationStyle
    ) -> PresentationOccurrence? {
        guard
            let activePresentation,
            AnyHashable(activePresentation.item.id) == AnyHashable(item.id),
            activePresentation.descriptor.style == style
        else {
            return nil
        }
        return PresentationOccurrence(identity: activePresentation.identity)
    }

    @discardableResult
    func mountPresentation(
        _ occurrence: PresentationOccurrence?,
        in sceneIdentifier: RUMSceneIdentifier,
        viewsHandler: RUMViewsHandler?
    ) -> Bool {
        guard
            let occurrence,
            var activePresentation,
            activePresentation.identity == occurrence.identity,
            let viewsHandler,
            viewsHandler.canTrackViews(in: sceneIdentifier)
        else {
            return false
        }

        if activePresentation.isStarted,
           activePresentation.sceneIdentifier == sceneIdentifier {
            return true
        }

        let mountedPresentation = activePresentation.isStarted
            ? activePresentation
            : outgoingPresentation
        let view = activePresentation.descriptor.view
        let accepted: Bool
        if
            let mountedPresentation,
            mountedPresentation.isStarted,
            let previousSceneIdentifier = mountedPresentation.sceneIdentifier {
            accepted = viewsHandler.notify_semanticPresentationReplace(
                identity: mountedPresentation.identity,
                sceneIdentifier: previousSceneIdentifier,
                replacementIdentity: activePresentation.identity,
                replacementName: view.name,
                replacementPath: view.path ?? view.name,
                replacementAttributes: view.attributes,
                replacementSceneIdentifier: sceneIdentifier
            )
        } else {
            accepted = viewsHandler.notify_semanticPresentationAppear(
                identity: activePresentation.identity,
                name: view.name,
                path: view.path ?? view.name,
                attributes: view.attributes,
                sceneIdentifier: sceneIdentifier
            )
        }
        guard accepted else {
            return false
        }
        outgoingPresentation = nil
        activePresentation.sceneIdentifier = sceneIdentifier
        activePresentation.isStarted = true
        activePresentation.hasMounted = true
        self.activePresentation = activePresentation
        return true
    }

    /// A SwiftUI presentation can rematerialize its content while the same
    /// accepted item remains presented. Read the application's accepted value
    /// before treating a content disappearance as a semantic dismissal.
    func presentationDidDisappear(
        _ occurrence: PresentationOccurrence?,
        acceptedItem: Presentation?,
        descriptor: (Presentation) -> RUMNavigationPresentation,
        viewsHandler: RUMViewsHandler?
    ) {
        guard
            let occurrence,
            activePresentation?.identity == occurrence.identity
        else {
            return
        }
        reconcilePresentation(acceptedItem, descriptor: descriptor, viewsHandler: viewsHandler)
    }

    func consumeDismissed(
        style: RUMNavigationPresentationStyle
    ) -> Presentation? {
        switch style {
        case .sheet:
            defer { dismissedSheet = nil }
            return dismissedSheet
        case .fullScreenCover:
            defer { dismissedFullScreenCover = nil }
            return dismissedFullScreenCover
        }
    }

    /// Balances the last mounted presentation when its semantic container is
    /// removed before a pending replacement can mount. Ordinary presentation
    /// disappearance remains owned by `presentationDidDisappear`.
    func cancelPresentations(viewsHandler: RUMViewsHandler?) {
        finishActivePresentation(viewsHandler: viewsHandler, recordsDismissal: false)
    }

    /// Drops presentation and attachment state after the view handler has
    /// stopped the disconnected scene. No additional RUM stop is emitted.
    func sceneDidDisconnect(_ sceneIdentifier: RUMSceneIdentifier) {
        let ownsScene = engine.sceneIdentifier == sceneIdentifier
            || activePresentation?.sceneIdentifier == sceneIdentifier
            || outgoingPresentation?.sceneIdentifier == sceneIdentifier
        guard ownsScene else {
            return
        }
        if engine.sceneIdentifier == sceneIdentifier {
            engine.reconcile(attachment: .detached)
        }
        activePresentation = nil
        outgoingPresentation = nil
        dismissedSheet = nil
        dismissedFullScreenCover = nil
    }

    private func finishActivePresentation(
        viewsHandler: RUMViewsHandler?,
        recordsDismissal: Bool
    ) {
        guard let activePresentation else {
            return
        }

        let mountedPresentation: ActivePresentation?
        if activePresentation.isStarted {
            mountedPresentation = activePresentation
        } else {
            mountedPresentation = outgoingPresentation
        }
        if
            let mountedPresentation,
            let sceneIdentifier = mountedPresentation.sceneIdentifier {
            viewsHandler?.notify_semanticPresentationDisappear(
                identity: mountedPresentation.identity,
                sceneIdentifier: sceneIdentifier
            )
        }

        if recordsDismissal && activePresentation.hasMounted {
            switch activePresentation.descriptor.style {
            case .sheet:
                dismissedSheet = activePresentation.item
            case .fullScreenCover:
                dismissedFullScreenCover = activePresentation.item
            }
        }
        self.activePresentation = nil
        outgoingPresentation = nil
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
private struct RUMSemanticNavigationDestinationBoundary<
    Route: Hashable,
    Presentation: Identifiable,
    Content: SwiftUI.View
>: SwiftUI.View {
    let route: Route
    let rumView: RUMView
    let navigationState: RUMSwiftUISemanticNavigationState<Route, Presentation>
    let core: DatadogCoreProtocol
    @ViewBuilder let content: Content

    @State private var occurrenceClaim:
        RUMSwiftUISemanticNavigationState<Route, Presentation>.RouteOccurrenceClaim

    init(
        route: Route,
        rumView: RUMView,
        navigationState: RUMSwiftUISemanticNavigationState<Route, Presentation>,
        core: DatadogCoreProtocol,
        @ViewBuilder content: () -> Content
    ) {
        self.route = route
        self.rumView = rumView
        self.navigationState = navigationState
        self.core = core
        self.content = content()
        self._occurrenceClaim = State(
            initialValue: navigationState.makeOccurrenceClaim(for: route)
        )
    }

    var body: some SwiftUI.View {
        let occurrence = navigationState.occurrence(
            for: route,
            retaining: occurrenceClaim
        )
        return content.trackRUMView(
            rumView: rumView,
            occurrenceKey: occurrence.key,
            bindingGeneration: occurrence.generation,
            isCurrentDestination: occurrence.isCurrentDestination,
            navigationOccurrenceSource: navigationState.occurrenceSource,
            in: core
        )
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
private struct RUMSemanticPresentationBoundary<
    Presentation: Identifiable,
    Content: SwiftUI.View
>: SwiftUI.View {
    let mount: (RUMSceneIdentifier) -> Bool
    let disappear: () -> Void
    let instrumentation: RUMInstrumentation?
    @ViewBuilder let content: Content

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    @State private var suppressionState = RUMSwiftUIAutomaticViewSuppressionState()

    init<Route: Hashable>(
        occurrence: RUMSwiftUISemanticNavigationState<Route, Presentation>.PresentationOccurrence?,
        navigationState: RUMSwiftUISemanticNavigationState<Route, Presentation>,
        acceptedPresentation: Binding<Presentation?>,
        descriptor: @escaping (Presentation) -> RUMNavigationPresentation,
        instrumentation: RUMInstrumentation?,
        @ViewBuilder content: () -> Content
    ) {
        self.instrumentation = instrumentation
        self.mount = { sceneIdentifier in
            navigationState.mountPresentation(
                occurrence,
                in: sceneIdentifier,
                viewsHandler: instrumentation?.viewsHandler
            )
        }
        self.disappear = {
            navigationState.presentationDidDisappear(
                occurrence,
                acceptedItem: acceptedPresentation.wrappedValue,
                descriptor: descriptor,
                viewsHandler: instrumentation?.viewsHandler
            )
        }
        self.content = content()
    }

    var body: some SwiftUI.View {
        content
            .background(
                RUMSceneIdentifierReader(
                    applicationSupportsMultipleScenes: true,
                    initialSceneIdentifier: initialSceneIdentifier,
                    onCreate: { observer in
                        instrumentation?.swiftUIViewAuthorityRegistry?.register(
                            observer: observer,
                            suppressionState: suppressionState
                        )
                    },
                    onInitialMount: activate(in:),
                    onMount: activate(in:),
                    onChange: { attachment in
                        if case .attached(let sceneIdentifier?) = attachment {
                            activate(in: sceneIdentifier)
                        }
                    }
                )
            )
            .onAppear {
                if let initialSceneIdentifier {
                    activate(in: initialSceneIdentifier)
                }
            }
            .onDisappear {
                disappear()
                suppressionState.disappear()
            }
    }

    private var initialSceneIdentifier: RUMSceneIdentifier? {
        sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    private func activate(in sceneIdentifier: RUMSceneIdentifier) {
        if mount(sceneIdentifier) {
            suppressionState.appear()
        } else {
            suppressionState.disappear()
        }
    }
}

@available(iOS 27.0, visionOS 27.0, *)
@MainActor
internal final class RUMSemanticNavigationContainerLifetimeState {
    private var attachmentGeneration: UInt64 = 0

    func reconcile(
        attachment: RUMViewTrackingState.Attachment,
        onFinalDetach: @escaping () -> Void
    ) {
        attachmentGeneration &+= 1
        guard attachment == .detached else {
            return
        }

        let expectedGeneration = attachmentGeneration
        DispatchQueue.main.async { [self] in
            guard attachmentGeneration == expectedGeneration else {
                return
            }
            onFinalDetach()
        }
    }
}

/// Detects removal of the semantic container without conflating it with root
/// navigation callbacks or presentations. A one-turn grace period absorbs
/// SwiftUI's transient representable detach/reattach cycles.
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
private struct RUMSemanticNavigationHostLifetimeModifier: SwiftUI.ViewModifier {
    let engine: RUMSwiftUISemanticNavigationEngine
    let viewsHandler: RUMViewsHandler?
    let notificationCenter: NotificationCenter
    let authorityRegistry: RUMSwiftUIViewAuthorityRegistry?
    let suppressionState: RUMSwiftUIAutomaticViewSuppressionState?
#if DEBUG
    var testingOnReaderCreate: ((RUMSceneIdentifierReader.ObserverView) -> Void)?
        = nil
#endif
    let onInitialSceneAttachment: ((RUMSceneIdentifier) -> Void)?
    let onAttachment: (RUMViewTrackingState.Attachment) -> Void
    let onSceneDisconnect: (RUMSceneIdentifier) -> Void
    let onFinalDetach: () -> Void

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    @State private var lifetimeState = RUMSemanticNavigationContainerLifetimeState()

    init(
        engine: RUMSwiftUISemanticNavigationEngine,
        viewsHandler: RUMViewsHandler?,
        notificationCenter: NotificationCenter,
        authorityRegistry: RUMSwiftUIViewAuthorityRegistry? = nil,
        suppressionState: RUMSwiftUIAutomaticViewSuppressionState? = nil,
        onInitialSceneAttachment: ((RUMSceneIdentifier) -> Void)? = nil,
        onAttachment: @escaping (RUMViewTrackingState.Attachment) -> Void = { _ in },
        onSceneDisconnect: @escaping (RUMSceneIdentifier) -> Void,
        onFinalDetach: @escaping () -> Void
    ) {
        self.engine = engine
        self.viewsHandler = viewsHandler
        self.notificationCenter = notificationCenter
        self.authorityRegistry = authorityRegistry
        self.suppressionState = suppressionState
        self.onInitialSceneAttachment = onInitialSceneAttachment
        self.onAttachment = onAttachment
        self.onSceneDisconnect = onSceneDisconnect
        self.onFinalDetach = onFinalDetach
    }

#if DEBUG
    init(
        engine: RUMSwiftUISemanticNavigationEngine,
        viewsHandler: RUMViewsHandler?,
        notificationCenter: NotificationCenter,
        authorityRegistry: RUMSwiftUIViewAuthorityRegistry? = nil,
        suppressionState: RUMSwiftUIAutomaticViewSuppressionState? = nil,
        testingOnReaderCreate:
            ((RUMSceneIdentifierReader.ObserverView) -> Void)?,
        onInitialSceneAttachment: ((RUMSceneIdentifier) -> Void)? = nil,
        onAttachment: @escaping (RUMViewTrackingState.Attachment) -> Void = { _ in },
        onSceneDisconnect: @escaping (RUMSceneIdentifier) -> Void,
        onFinalDetach: @escaping () -> Void
    ) {
        self.init(
            engine: engine,
            viewsHandler: viewsHandler,
            notificationCenter: notificationCenter,
            authorityRegistry: authorityRegistry,
            suppressionState: suppressionState,
            onInitialSceneAttachment: onInitialSceneAttachment,
            onAttachment: onAttachment,
            onSceneDisconnect: onSceneDisconnect,
            onFinalDetach: onFinalDetach
        )
        self.testingOnReaderCreate = testingOnReaderCreate
    }
#endif

    func body(content: Content) -> some SwiftUI.View {
        reconcileInitialSceneAttachment()
        return content
            .background(
                RUMSceneIdentifierReader(
                    applicationSupportsMultipleScenes: true,
                    initialSceneIdentifier: initialSceneIdentifier,
                    onCreate: { observer in
#if DEBUG
                        testingOnReaderCreate?(observer)
#endif
                        guard let suppressionState else {
                            return
                        }
                        authorityRegistry?.register(
                            observer: observer,
                            suppressionState: suppressionState
                        )
                    },
                    onInitialMount: reconcileInitialTrait(sceneIdentifier:),
                    onMount: reconcile(sceneIdentifier:),
                    onChange: { attachment in
                        reconcile(attachment: attachment)
                    }
                )
            )
            .onReceive(
                notificationCenter.publisher(for: UIScene.didDisconnectNotification)
            ) { notification in
                guard
                    let sceneIdentifier = viewsHandler?
                        .sceneIdentifierForLifecycleNotification(notification)
                else {
                    return
                }
                onSceneDisconnect(sceneIdentifier)
            }
    }

    /// The scene trait is available while SwiftUI evaluates the host, before
    /// descendant `onAppear` and task callbacks. Reconcile here so a source
    /// with an initial destination can establish its first RUM occurrence
    /// before customer lifecycle work is emitted.
    private func reconcileInitialSceneAttachment() {
        guard let initialSceneIdentifier else {
            return
        }
        reconcileInitialTrait(sceneIdentifier: initialSceneIdentifier)
    }

    private func reconcileInitialTrait(sceneIdentifier: RUMSceneIdentifier) {
        if let onInitialSceneAttachment {
            onInitialSceneAttachment(sceneIdentifier)
        } else {
            reconcile(attachment: .attached(sceneIdentifier))
        }
    }

    private var initialSceneIdentifier: RUMSceneIdentifier? {
        sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    private func reconcile(sceneIdentifier: RUMSceneIdentifier) {
        reconcile(attachment: .attached(sceneIdentifier))
    }

    private func reconcile(attachment: RUMViewTrackingState.Attachment) {
        engine.reconcile(attachment: attachment)
        onAttachment(attachment)
        lifetimeState.reconcile(attachment: attachment) {
            engine.cancelNavigationOwnedOccurrences(viewsHandler: viewsHandler)
            onFinalDetach()
        }
    }
}

/// An experimental instrumentation host for customer-owned navigation content.
///
/// The host attaches a scene-scoped semantic engine without replacing the
/// customer's visual navigation container. Opaque content continues through
/// ordinary automatic view tracking unless an exact transition source is
/// supplied explicitly or through the optional capability.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
public struct RUMNavigationHost<Content: SwiftUI.View>: SwiftUI.View {
    private let core: DatadogCoreProtocol
    private let explicitTransitions: RUMNavigationTransitions?
    private let allowsCapabilityFallback: Bool
    @StateObject private var observedTransitions: RUMNavigationObservedTransitions
#if DEBUG
    private let testingOnLifetimeReaderCreate:
        ((RUMSceneIdentifierReader.ObserverView) -> Void)?
    private let testingOnFinalDetach: (() -> Void)?
#endif
    private let content: Content

    @State private var hostState = RUMSemanticNavigationHostState()

    public init(
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.explicitTransitions = nil
        self.allowsCapabilityFallback = true
        self._observedTransitions = StateObject(
            wrappedValue: RUMNavigationObservedTransitions()
        )
#if DEBUG
        self.testingOnLifetimeReaderCreate = nil
        self.testingOnFinalDetach = nil
#endif
        self.content = content()
    }

    public init(
        transitions: RUMNavigationTransitions,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.explicitTransitions = transitions
        self.allowsCapabilityFallback = false
        self._observedTransitions = StateObject(
            wrappedValue: RUMNavigationObservedTransitions()
        )
#if DEBUG
        self.testingOnLifetimeReaderCreate = nil
        self.testingOnFinalDetach = nil
#endif
        self.content = content()
    }

    /// Observes an application's existing accepted navigation-state stream once
    /// at its container boundary. The destination projection identifies only
    /// the currently visible root, route, or presentation; it does not require
    /// an exhaustive RUM metadata resolver or calls in navigation methods.
    public init<State, Updates: Publisher>(
        observing updates: Updates,
        destination: @MainActor @escaping (State) -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata = .automatic,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) where Updates.Output == State, Updates.Failure == Never {
        self.core = core
        self.explicitTransitions = nil
        self.allowsCapabilityFallback = false
        self._observedTransitions = StateObject(
            wrappedValue: RUMNavigationObservedTransitions(
                updates: updates,
                destination: destination,
                metadata: metadata
            )
        )
#if DEBUG
        self.testingOnLifetimeReaderCreate = nil
        self.testingOnFinalDetach = nil
#endif
        self.content = content()
    }

#if compiler(>=6.4)
    /// Observes one atomically updated accepted-state property on an existing
    /// iOS 27 `@Observable` router once at its container boundary, without
    /// exposing Observation framework types in the API.
    ///
    /// The projection identifies the currently accepted root, route, or
    /// presentation. It must be stable, side-effect-free, and derive from one
    /// accepted-state property. Independently mutating multiple tracked
    /// properties represents multiple committed states and can expose an
    /// intermediate destination. The projection is evaluated once initially
    /// and synchronously after every tracked `.didSet`; customer navigation
    /// methods and standard SwiftUI containers remain unchanged.
    public init(
        observingCurrentDestination: @MainActor @escaping () ->
            RUMNavigationDestination,
        metadata: RUMNavigationMetadata = .automatic,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.explicitTransitions = nil
        self.allowsCapabilityFallback = false
        self._observedTransitions = StateObject(
            wrappedValue: RUMNavigationObservedTransitions(
                observingCurrentDestination: observingCurrentDestination,
                metadata: metadata
            )
        )
#if DEBUG
        self.testingOnLifetimeReaderCreate = nil
        self.testingOnFinalDetach = nil
#endif
        self.content = content()
    }
#endif

#if DEBUG
    /// Test-only integration seam used by the native multi-scene probe to
    /// exercise the actual host lifetime reader. It deliberately remains
    /// internal so no probe control leaks into the experimental customer API.
    internal init(
        transitions: RUMNavigationTransitions,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        testingOnLifetimeReaderCreate:
            @escaping (RUMSceneIdentifierReader.ObserverView) -> Void,
        testingOnFinalDetach: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.explicitTransitions = transitions
        self.allowsCapabilityFallback = false
        self._observedTransitions = StateObject(
            wrappedValue: RUMNavigationObservedTransitions()
        )
        self.testingOnLifetimeReaderCreate = testingOnLifetimeReaderCreate
        self.testingOnFinalDetach = testingOnFinalDetach
        self.content = content()
    }
#endif

    public var body: some SwiftUI.View {
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        hostState.reconcile(
            transitions: Self.resolveTransitions(
                explicit: explicitTransitions ?? observedTransitions.transitions,
                content: content,
                allowsCapabilityFallback: allowsCapabilityFallback
            ),
            viewsHandler: instrumentation?.viewsHandler
        )
#if DEBUG
        let lifetimeModifier = RUMSemanticNavigationHostLifetimeModifier(
                engine: hostState.engine,
                viewsHandler: instrumentation?.viewsHandler,
                notificationCenter: instrumentation?.viewsHandler
                    .lifecycleNotificationCenter ?? .default,
                authorityRegistry: instrumentation?.swiftUIViewAuthorityRegistry,
                suppressionState: hostState.suppressionState,
                testingOnReaderCreate: testingOnLifetimeReaderCreate,
                onInitialSceneAttachment: hostState.reconcile(initialSceneIdentifier:),
                onAttachment: { attachment in
                    hostState.reconcile(attachment: attachment)
                },
                onSceneDisconnect: { sceneIdentifier in
                    hostState.sceneDidDisconnect(sceneIdentifier)
                },
                onFinalDetach: {
                    hostState.finalDetach()
                    testingOnFinalDetach?()
                }
            )
#else
        let lifetimeModifier = RUMSemanticNavigationHostLifetimeModifier(
            engine: hostState.engine,
            viewsHandler: instrumentation?.viewsHandler,
            notificationCenter: instrumentation?.viewsHandler
                .lifecycleNotificationCenter ?? .default,
            authorityRegistry: instrumentation?.swiftUIViewAuthorityRegistry,
            suppressionState: hostState.suppressionState,
            onInitialSceneAttachment: hostState.reconcile(initialSceneIdentifier:),
            onAttachment: { attachment in
                hostState.reconcile(attachment: attachment)
            },
            onSceneDisconnect: { sceneIdentifier in
                hostState.sceneDidDisconnect(sceneIdentifier)
            },
            onFinalDetach: {
                hostState.finalDetach()
            }
        )
#endif
        return content.modifier(lifetimeModifier)
    }

    internal static func resolveTransitions(
        explicit: RUMNavigationTransitions?,
        content: Content,
        allowsCapabilityFallback: Bool = true
    ) -> RUMNavigationTransitions? {
        if let explicit {
            return explicit
        }
        guard allowsCapabilityFallback else {
            return nil
        }
        return (content as? any RUMNavigationTransitionProviding)?
            .rumNavigationTransitions
    }
}

/// An experimental semantic SwiftUI navigation container. It owns destination
/// materialization so RUM can create one view occurrence for each committed path
/// destination while automatic tracking remains enabled outside this container.
@_spi(Experimental)
@available(iOS 27.0, visionOS 27.0, *)
@MainActor
public struct RUMNavigationStack<
    Route: Hashable,
    Presentation: Identifiable,
    Root: SwiftUI.View,
    Destination: SwiftUI.View,
    Presented: SwiftUI.View
>: SwiftUI.View {
    private let path: Binding<[Route]>
    private let presented: Binding<Presentation?>
    private let root: RUMView
    private let destination: (Route) -> RUMView
    private let presentation: (Presentation) -> RUMNavigationPresentation
    private let core: DatadogCoreProtocol
    private let rootContent: Root
    private let destinationContent: (Route) -> Destination
    private let presentedContent: (Presentation) -> Presented
    private let onPresentationDismiss: (Presentation) -> Void

    @State private var navigationState =
        RUMSwiftUISemanticNavigationState<Route, Presentation>()

    public init(
        path: Binding<[Route]>,
        presented: Binding<Presentation?>,
        root: RUMView,
        destination: @escaping (Route) -> RUMView,
        presentation: @escaping (Presentation) -> RUMNavigationPresentation,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder rootContent: () -> Root,
        @ViewBuilder destinationContent: @escaping (Route) -> Destination,
        @ViewBuilder presentedContent: @escaping (Presentation) -> Presented,
        onPresentationDismiss: @escaping (Presentation) -> Void = { _ in }
    ) {
        self.path = path
        self.presented = presented
        self.root = root
        self.destination = destination
        self.presentation = presentation
        self.core = core
        self.rootContent = rootContent()
        self.destinationContent = destinationContent
        self.presentedContent = presentedContent
        self.onPresentationDismiss = onPresentationDismiss
    }

    public var body: some SwiftUI.View {
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        navigationState.reconcile(path: path.wrappedValue)
        navigationState.reconcileCurrentDestination(
            root: root,
            rootType: Root.self,
            destination: destination,
            destinationType: Destination.self,
            viewsHandler: instrumentation?.viewsHandler
        )
        navigationState.reconcilePresentation(
            presented.wrappedValue,
            descriptor: presentation,
            viewsHandler: instrumentation?.viewsHandler
        )

        return NavigationStack(path: trackedPath) {
            tracked(rootContent, as: root, occurrence: navigationState.rootOccurrence)
                .navigationDestination(for: Route.self) { route in
                    RUMSemanticNavigationDestinationBoundary(
                        route: route,
                        rumView: destination(route),
                        navigationState: navigationState,
                        core: core
                    ) {
                        destinationContent(route)
                    }
                }
        }
        .sheet(
            item: presentationBinding(for: .sheet),
            onDismiss: { deliverDismissal(for: .sheet) }
        ) { item in
            semanticPresentation(item, style: .sheet, instrumentation: instrumentation)
        }
        .fullScreenCover(
            item: presentationBinding(for: .fullScreenCover),
            onDismiss: { deliverDismissal(for: .fullScreenCover) }
        ) { item in
            semanticPresentation(item, style: .fullScreenCover, instrumentation: instrumentation)
        }
        .modifier(
            RUMSemanticNavigationHostLifetimeModifier(
                engine: navigationState.engine,
                viewsHandler: instrumentation?.viewsHandler,
                notificationCenter: instrumentation?.viewsHandler
                    .lifecycleNotificationCenter ?? .default,
                onSceneDisconnect: { sceneIdentifier in
                    navigationState.sceneDidDisconnect(sceneIdentifier)
                },
                onFinalDetach: {
                    navigationState.cancelPresentations(
                        viewsHandler: instrumentation?.viewsHandler
                    )
                }
            )
        )
    }

    private var trackedPath: Binding<[Route]> {
        Binding(
            get: { path.wrappedValue },
            set: { newPath, transaction in
                navigationState.forward(
                    proposedPath: newPath,
                    to: path,
                    transaction: transaction
                )
            }
        )
    }

    private func presentationBinding(
        for style: RUMNavigationPresentationStyle
    ) -> Binding<Presentation?> {
        navigationState.presentationBinding(
            for: style,
            to: presented,
            descriptor: presentation,
            viewsHandler: { core.get(feature: RUMFeature.self)?.instrumentation.viewsHandler }
        )
    }

    private func semanticPresentation(
        _ item: Presentation,
        style: RUMNavigationPresentationStyle,
        instrumentation: RUMInstrumentation?
    ) -> some SwiftUI.View {
        let occurrence = navigationState.presentationOccurrence(for: item, style: style)
        return RUMSemanticPresentationBoundary(
            occurrence: occurrence,
            navigationState: navigationState,
            acceptedPresentation: presented,
            descriptor: presentation,
            instrumentation: instrumentation
        ) {
            presentedContent(item)
        }
        .id(occurrence)
    }

    private func tracked<Content: SwiftUI.View>(
        _ content: Content,
        as rumView: RUMView,
        occurrence: RUMSwiftUISemanticNavigationState<Route, Presentation>.Occurrence
    ) -> some SwiftUI.View {
        content.trackRUMView(
            rumView: rumView,
            occurrenceKey: occurrence.key,
            bindingGeneration: occurrence.generation,
            isCurrentDestination: occurrence.isCurrentDestination,
            navigationOccurrenceSource: navigationState.occurrenceSource,
            in: core
        )
    }

    private func deliverDismissal(for style: RUMNavigationPresentationStyle) {
        guard let item = navigationState.consumeDismissed(style: style) else {
            return
        }
        onPresentationDismiss(item)
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
        #if os(iOS) || os(visionOS)
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: name,
                path: path,
                attributes: attributes,
                configuration: nil,
                navigationOccurrenceSource: nil
            )
        )
        #else
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: name,
                path: path,
                attributes: attributes
            )
        )
        #endif
    }
}

#if os(iOS)
internal extension SwiftUI.View {
    /// Internal seam for semantic navigation occurrence identity without
    /// changing the public API or SwiftUI identity of customer content.
    func trackRUMView(
        name: String,
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        isCurrentDestination: Bool = true,
        navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource? = nil,
        attributes: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        let path = "\(name)/\(typeDescription.hashValue)"
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        let configuration = RUMViewTrackingState.Configuration(
            occurrenceKey: occurrenceKey,
            bindingGeneration: bindingGeneration,
            descriptor: .init(name: name, path: path, attributes: attributes),
            isCurrentDestination: isCurrentDestination
        )
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: name,
                path: path,
                attributes: attributes,
                configuration: configuration,
                navigationOccurrenceSource: navigationOccurrenceSource
            )
        )
    }

    func trackRUMView(
        rumView: RUMView,
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        isCurrentDestination: Bool = true,
        navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource? = nil,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        let path = rumView.path ?? "\(rumView.name)/\(typeDescription.hashValue)"
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        let configuration = RUMViewTrackingState.Configuration(
            occurrenceKey: occurrenceKey,
            bindingGeneration: bindingGeneration,
            descriptor: .init(
                name: rumView.name,
                path: path,
                attributes: rumView.attributes
            ),
            isCurrentDestination: isCurrentDestination
        )
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: rumView.name,
                path: path,
                attributes: rumView.attributes,
                configuration: configuration,
                navigationOccurrenceSource: navigationOccurrenceSource
            )
        )
    }

    /// Internal seam for validating a centralized semantic presentation
    /// owner alongside automatic tracking. It intentionally publishes no RUM
    /// view commands of its own.
    func suppressAutomaticRUMViewTracking(
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        return modifier(
            RUMAutomaticViewSuppressionModifier(instrumentation: instrumentation)
        )
    }
}
#endif

#endif
