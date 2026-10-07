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

/// Opaque identity supplied by a future navigation-aware integration to
/// distinguish semantic route occurrences without changing SwiftUI's own view
/// identity. The value remains local control data and is never logged or sent.
internal struct RUMViewOccurrenceKey: Hashable {
    private let value: AnyHashable

    init<Value: Hashable>(_ value: Value) {
        self.value = AnyHashable(value)
    }
}
#endif // os(iOS)

#if os(iOS)

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
    private(set) var admission: RUMSwiftUIViewCallbackAdmission?

    @MainActor
    func bindAdmission(_ admission: RUMSwiftUIViewCallbackAdmission) {
        guard admission.isValid, self.admission == nil else { return }
        self.admission = admission
    }

    init(
        identity: String = UUID().uuidString,
        occurrenceIdentityGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.identity = identity
        self.occurrenceIdentityGenerator = occurrenceIdentityGenerator
    }

    @MainActor
    func update(attachment: Attachment) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    @MainActor
    func appear() -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: nil,
            attachment: nil,
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    @MainActor
    func mount(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    /// Handles the platform reader becoming mounted. Unlike a semantic
    /// appearance, routine representable updates must not restart a view that
    /// has already disappeared. Reader mounts are authoritative only for an
    /// initial mount, an active occurrence, or recovery after scene teardown.
    @MainActor
    func mountFromReader(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    /// The environment trait can seed the first mount before UIKit attaches
    /// the reader. It is not sufficient evidence for recovery because a
    /// disconnected scene may keep publishing its stale trait value.
    @MainActor
    func mountFromInitialTrait(in sceneIdentifier: RUMSceneIdentifier) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        guard acceptsInitialTraitMount else {
            return []
        }
        return mount(in: sceneIdentifier)

        }()
    }

    @MainActor
    func disappear() -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: nil,
            attachment: nil,
            isAppeared: false,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    @MainActor
    func update(configuration: Configuration, attachment: Attachment) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: configuration,
            attachment: attachment,
            isAppeared: nil,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    /// Restores bookkeeping for a materialized navigation boundary that is not
    /// the container's current destination. This is used after the boundary's
    /// state temporarily lent scene proof and occurrence ownership to an
    /// initially restored top route. It never ends or creates an occurrence;
    /// active navigation remains under the interactive transition arbiter.
    @discardableResult
    @MainActor
    func recordDormantNavigationBoundary(
        configuration: Configuration,
        attachment: Attachment
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
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
    @MainActor
    func canPromoteDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        allowsSceneMigration: Bool = false
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Whether a retained reader may commit the source-accepted key without
    /// publishing an occurrence. This accepts either the still-attached reader
    /// or a subsequent detached reconciliation, but both require the same last
    /// concrete scene proof.
    @MainActor
    func canSettleDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

        canResolveDormantNavigationBoundary(
            from: expectedDormantConfiguration,
            to: configuration
        ) && !requiresRemount
            && lastProvenSceneIdentifier == sceneIdentifier
            && (attachment == .attached(sceneIdentifier) || attachment == .detached)

        }()
    }

    @MainActor
    private func canResolveDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Atomically promotes a source-authorized dormant boundary. This is the
    /// only source-authorized exception to the ordinary binding fence, and it
    /// still participates in interactive-transition deferral by checking the
    /// revision captured by the arbiter.
    @MainActor
    func promoteDormantNavigationBoundary(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        expectedRevision: UInt64? = nil,
        allowsSceneMigration: Bool = false
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    /// Commits the accepted key without publishing an occurrence when the
    /// final interactive state is no longer both appeared and attached to the
    /// proved scene. This prevents a later accepted lifecycle callback from
    /// being rejected by the former speculative key's generation fence.
    @MainActor
    func settleDormantNavigationPromotion(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64? = nil
    ) {
        guard admission?.isValid == true else { return }
        return {

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

        }()
    }

    /// Preserves a source-authorized canonicalization when its scene
    /// disconnects before an interactive transition resolves. No occurrence is
    /// published for the disappearing scene; the accepted configuration and
    /// appearance proof are consumed only by a subsequent concrete reader
    /// mount.
    @discardableResult
    @MainActor
    func preserveDormantNavigationPromotionAfterSceneDisconnect(
        from expectedDormantConfiguration: Configuration,
        to configuration: Configuration
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Re-establishes scene proof for a hidden navigation boundary after its
    /// former scene disconnected. The navigation source has already established
    /// that this reader is not the accepted destination, so rearming must update
    /// bookkeeping without creating a view occurrence.
    @discardableResult
    @MainActor
    func rearmDormantNavigationBoundaryAfterSceneDisconnect(
        configuration: Configuration,
        attachment: Attachment
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Prepares an inactive replacement reader to own the source's last proven
    /// destination. Its dormant boundary can be from a newer binding snapshot
    /// whose destination descriptor has not arrived yet. A previously used
    /// reader is eligible only when its last-started generation belongs to that
    /// proven destination and its local state is either the destination or the
    /// source-validated boundary. This preflight never publishes a transition.
    @discardableResult
    @MainActor
    func prepareSourceManagedNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration,
        boundaryConfiguration: Configuration
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    @MainActor
    func mount(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: configuration,
            attachment: .attached(sceneIdentifier),
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: true
        )

        }()
    }

    /// Starts an initial navigation destination using the scene proved by the
    /// container's root reader. The root can reconcile its own dormant
    /// configuration before that reader mounts, so this narrowly permits the
    /// never-started state to adopt the top destination from the same binding
    /// generation. Once any occurrence has started, ordinary generation fences
    /// remain authoritative.
    @MainActor
    func mountInitialNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        if
            activeOccurrence == nil,
            lifecycleGeneration == 0,
            lastStartedBindingGeneration == nil,
            !requiresRemount,
            (self.configuration?.bindingGeneration ?? 0) <= configuration.bindingGeneration {
            self.configuration = nil
        }
        return mount(in: sceneIdentifier, configuration: configuration)

        }()
    }

    /// Recreates the same accepted navigation occurrence after the owning scene
    /// was torn down. `invalidateAfterSceneDisconnect` is the only operation
    /// that arms this same-generation exception; ordinary lifecycle callbacks
    /// remain unable to resurrect an ended occurrence.
    @MainActor
    func mountCurrentNavigationDestinationAfterSceneDisconnect(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    /// Checks the exact configuration fence used for reliable reader recovery
    /// after scene teardown. The navigation source also uses this as a
    /// preflight before ending an occurrence owned by another reader.
    @MainActor
    func canRecoverNavigationDestinationAfterSceneDisconnect(
        _ configuration: Configuration
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

        requiresRemount
            && activeOccurrence == nil
            && self.configuration == configuration
            && lastStartedBindingGeneration == configuration.bindingGeneration

        }()
    }

    /// Recreates an occurrence after the navigation source deliberately ended
    /// its same-generation owner while moving that boundary to another scene.
    /// This is intentionally narrower than an ordinary reader mount: only the
    /// source calls it immediately after balancing the prior occurrence.
    @MainActor
    func remountSourceManagedNavigationDestination(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    /// Checks the narrow same-generation restart used by a navigation source
    /// after it has balanced the occurrence currently owned by another reader.
    /// Keeping this preflight separate prevents the source from stopping the
    /// live owner before discovering that the replacement cannot take over.
    @MainActor
    func canRemountSourceManagedNavigationDestination(
        _ configuration: Configuration
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

        !requiresRemount
            && activeOccurrence == nil
            && !isAppeared
            && lifecycleGeneration > 0
            && self.configuration == configuration
            && lastStartedBindingGeneration == configuration.bindingGeneration

        }()
    }

    @MainActor
    func mountFromReader(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
    }

    @MainActor
    func mountFromInitialTrait(
        in sceneIdentifier: RUMSceneIdentifier,
        configuration: Configuration
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        guard acceptsInitialTraitMount else {
            return []
        }
        return mount(in: sceneIdentifier, configuration: configuration)

        }()
    }

    @MainActor
    func appear(configuration: Configuration) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: configuration,
            attachment: nil,
            isAppeared: true,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    @MainActor
    func disappear(configuration: Configuration) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: configuration,
            attachment: nil,
            isAppeared: false,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    /// Reconciles the final platform state in one step. Interactive navigation
    /// uses this to commit only the final lifecycle state after UIKit confirms
    /// the transition, instead of replaying speculative SwiftUI callbacks.
    @MainActor
    func reconcile(attachment: Attachment?, isAppeared: Bool?) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: nil,
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: nil,
            allowsRemount: false
        )

        }()
    }

    @MainActor
    func reconcile(
        configuration: Configuration,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64? = nil,
        allowsRemount: Bool = false
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: Optional(configuration),
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: expectedRevision,
            allowsRemount: allowsRemount
        )

        }()
    }

    @MainActor
    func reconcile(
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64,
        allowsRemount: Bool = false
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

        reconcile(
            configuration: nil,
            attachment: attachment,
            isAppeared: isAppeared,
            expectedRevision: expectedRevision,
            allowsRemount: allowsRemount
        )

        }()
    }

    @MainActor
    private func reconcile(
        configuration: Configuration?,
        attachment: Attachment?,
        isAppeared: Bool?,
        expectedRevision: UInt64?,
        allowsRemount: Bool
    ) -> [Transition] {
        guard admission?.isValid == true else { return [] }
        return {

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

        }()
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

    @MainActor
    func descriptor(for identity: String) -> Configuration.Descriptor? {
        guard admission?.isValid == true else { return nil }
        return {

        guard activeOccurrence?.identity == identity else {
            return nil
        }
        return activeOccurrence?.configuration?.descriptor

        }()
    }

    /// Keeps a navigation-owned occurrence alive while SwiftUI resolves whether
    /// the retained route will reuse this tracking state or mount a replacement.
    @MainActor
    func prepareForRetainedRouteHandoff(
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Transfers an already published occurrence to a replacement SwiftUI state
    /// without publishing another start. The replacement owns all later
    /// lifecycle callbacks, including the matching stop.
    @MainActor
    func transferRetainedRouteOccurrence(
        to target: RUMViewTrackingState,
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        guard target.admission?.isValid == true,
              target.admission?.binding.epoch == admission?.binding.epoch,
              target.admission?.binding.lifetime === admission?.binding.lifetime else { return false }
        return {

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

        }()
    }

    /// Moves a provisional source-owned occurrence to a replacement platform
    /// reader without publishing another start. Unlike retained-route adoption,
    /// the replacement state may already contain the donor boundary's dormant
    /// configuration; the source has validated that boundary before calling.
    @MainActor
    func transferSourceManagedNavigationDestination(
        to target: RUMViewTrackingState,
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        guard target.admission?.isValid == true,
              target.admission?.binding.epoch == admission?.binding.epoch,
              target.admission?.binding.lifetime === admission?.binding.lifetime else { return false }
        return {

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

        }()
    }

    @MainActor
    func settleRetainedRouteHandoff(
        configuration: Configuration,
        sceneIdentifier: RUMSceneIdentifier
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    /// Mirrors handler teardown after a scene disconnect without emitting a
    /// second stop. The state retains its keyed generation fence so callbacks
    /// from the disconnected reader cannot recreate the removed handler entry.
    /// A later platform mount is the only signal allowed to create a new
    /// occurrence.
    @discardableResult
    @MainActor
    func invalidateAfterSceneDisconnect(
        _ sceneIdentifier: RUMSceneIdentifier,
        forceForPending: Bool = false
    ) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    @MainActor
    private func accepts(_ configuration: Configuration) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    @MainActor
    func acceptsUnversioned(attachment: Attachment?, isAppeared: Bool?) -> Bool {
        guard admission?.isValid == true else { return false }
        return {

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

        }()
    }

    @MainActor
    private func start(in sceneIdentifier: RUMSceneIdentifier?) -> Transition? {
        guard admission?.isValid == true else { return nil }
        return {

        guard activeOccurrence == nil else {
            return nil
        }
        guard let occurrence = makeOccurrence(in: sceneIdentifier) else {
            return nil
        }
        activeOccurrence = occurrence
        return .start(identity: occurrence.identity, sceneIdentifier: sceneIdentifier)

        }()
    }

    @MainActor
    private func stopIfNeeded() -> Transition? {
        guard admission?.isValid == true else { return nil }
        return {

        guard let occurrence = activeOccurrence else {
            return nil
        }
        activeOccurrence = nil
        retainedRouteHandoffGeneration = nil
        return .stop(
            identity: occurrence.identity,
            sceneIdentifier: occurrence.sceneIdentifier
        )

        }()
    }

    @MainActor
    private func makeOccurrence(in sceneIdentifier: RUMSceneIdentifier?) -> ActiveOccurrence? {
        guard admission?.isValid == true else { return nil }
        guard let sceneIdentifier, admission?.admits(sceneIdentifier: sceneIdentifier) == true else { return nil }
        return {

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

        }()
    }

    @MainActor
    private func finishMutation(_ didMutate: Bool) {
        guard admission?.isValid == true else { return }
        return {

        if didMutate {
            revision &+= 1
        }

        }()
    }
}
#endif // os(iOS)

#endif // canImport(SwiftUI)
