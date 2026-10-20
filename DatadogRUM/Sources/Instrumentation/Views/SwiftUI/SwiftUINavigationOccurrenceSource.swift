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
        let originalAdmission: RUMSwiftUIViewCallbackAdmission?

        init(
            configuration: RUMViewTrackingState.Configuration,
            sceneIdentifier: RUMSceneIdentifier,
            state: RUMViewTrackingState
        ) {
            self.configuration = configuration
            self.sceneIdentifier = sceneIdentifier
            self.state = state
            originalAdmission = state.admission
        }
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
        let originalAdmission: RUMSwiftUIViewCallbackAdmission?

        init(
            configuration: RUMViewTrackingState.Configuration,
            boundaryConfiguration: RUMViewTrackingState.Configuration,
            boundaryAttachment: RUMViewTrackingState.Attachment,
            sceneIdentifier: RUMSceneIdentifier,
            state: RUMViewTrackingState,
            isAdopted: Bool
        ) {
            self.configuration = configuration
            self.boundaryConfiguration = boundaryConfiguration
            self.boundaryAttachment = boundaryAttachment
            self.sceneIdentifier = sceneIdentifier
            self.state = state
            self.isAdopted = isAdopted
            originalAdmission = state.admission
        }
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

    private let foundationBinding: RUMSwiftUIViewFoundationBinding

    init(binding: RUMSwiftUIViewFoundationBinding) {
        foundationBinding = binding
    }

    fileprivate func admits(_ admission: RUMSwiftUIViewCallbackAdmission) -> Bool {
        admission.isValid && foundationBinding.isValid
            && admission.binding.epoch == foundationBinding.epoch
            && admission.binding.lifetime === foundationBinding.lifetime
            && admission.binding.foundation === foundationBinding.foundation
    }

    private var registrations: [WeakRegistration] = []
    private var pendingRevealedRoute: PendingRevealedRoute?
    private var acceptedDestinationIdentity: DestinationIdentity?
    private var acceptedDestinationConfiguration: RUMViewTrackingState.Configuration?
    private var managedInitialOccurrence: ManagedInitialOccurrence?
    private var requiresInitialBootstrap = false
    private var awaitsCommittedRevealConfiguration = false

    // The record keeps its originating Session token. A valid incoming peer
    // does not adopt that token and must not be blocked by an expired record.
    private func admitsRecord(
        _ originalAdmission: RUMSwiftUIViewCallbackAdmission?,
        state: RUMViewTrackingState
    ) -> Bool {
        guard let originalAdmission, admits(originalAdmission) else { return false }
        return state.admission?.matches(originalAdmission) == true
    }

    private func pruneExpiredRecords() {
        if let owner = managedInitialOccurrence,
           !admitsRecord(owner.originalAdmission, state: owner.state) {
            managedInitialOccurrence = nil
            requiresInitialBootstrap = acceptedDestinationConfiguration != nil
            awaitsCommittedRevealConfiguration = false
        }
        if let pending = pendingRevealedRoute,
           !admitsRecord(pending.originalAdmission, state: pending.state) {
            pendingRevealedRoute = nil
        }
    }

    var isInitialDestinationPending: Bool {
        guard foundationBinding.isValid else { return false }
        pruneExpiredRecords()
        return requiresInitialBootstrap
    }

    var needsInitialDestinationReconciliation: Bool {
        guard foundationBinding.isValid else { return false }
        pruneExpiredRecords()
        return acceptedDestinationConfiguration == nil
    }

    /// Records the customer's accepted router destination before platform
    /// lifecycle callbacks can arrive. Descriptor reconciliation follows from
    /// `RUMNavigationStack.body`, but the occurrence key and generation are
    /// enough to reject delayed boundaries immediately.
    func acceptDestination(
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        change: DestinationChange
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

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
                , admission: admission)
            }
        }

        }()
    }

    /// Supplies the descriptor for the latest accepted destination. When a pop
    /// happens before the initial top adopts its provisional occurrence, this
    /// changes that occurrence into the already-materialized revealed boundary
    /// in the same synchronous router turn.
    @discardableResult
    func reconcileCurrentDestination(
        configuration: RUMViewTrackingState.Configuration,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> [RUMViewTrackingState.Transition] {
        guard admits(admission) else { return [] }
        pruneExpiredRecords()
        return {

        guard matchesAcceptedDestination(configuration, admission: admission) else {
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
            , admission: admission)
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
            admission: admission
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

        }()
    }

    /// Resolves one materialized boundary against the container's accepted
    /// destination. A non-current boundary may lend scene proof only while the
    /// initial restored destination has no owner. All other key/generation
    /// mismatches are stale and must not fall through to an ordinary mount.
    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        return {

        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            allowsDormantBoundaryPromotion: false,
            admission: admission,
            process: process
        )

        }()
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        allowsDormantBoundaryPromotion: Bool,
        admission: RUMSwiftUIViewCallbackAdmission,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        return {

        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            isReaderMount: true,
            allowsDormantBoundaryPromotion: allowsDormantBoundaryPromotion,
            admission: admission,
            process: process
        )

        }()
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        admission: RUMSwiftUIViewCallbackAdmission,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        return {

        resolveCandidate(
            candidateConfiguration: candidateConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            isReaderMount: isReaderMount,
            allowsDormantBoundaryPromotion: false,
            admission: admission,
            process: process
        )

        }()
    }

    func resolveCandidate(
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        allowsDormantBoundaryPromotion: Bool,
        admission: RUMSwiftUIViewCallbackAdmission,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        return {

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
                    admission: admission,
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
                admission: admission,
                process: process
            )
            return .handled
        }

        guard
            let acceptedDestinationConfiguration,
            matchesAcceptedDestination(candidateConfiguration, admission: admission)
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
               admission: admission
           ) {
            return pendingDisposition
        }

        if let owner = managedInitialOccurrence {
            if owner.configuration != acceptedDestinationConfiguration
                || owner.sceneIdentifier != sceneIdentifier {
                let movedSameDestinationToAnotherScene = owner.configuration
                    == acceptedDestinationConfiguration
                    && owner.sceneIdentifier != sceneIdentifier
                stopManagedInitialOccurrence(owner, admission: admission)
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
                    admission: admission,
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
                        admission: admission,
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
            admission: admission,
            process: process
        )
        return .handled

        }()
    }

    private func resolveManagedInitialBoundary(
        owner: ManagedInitialOccurrence,
        candidateConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        isReaderMount: Bool,
        admission: RUMSwiftUIViewCallbackAdmission,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        guard admitsRecord(owner.originalAdmission, state: owner.state) else { return .rejectStale }
        return {

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
                    admission: admission,
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
            stopManagedInitialOccurrence(owner, admission: admission)
        }
        managedInitialOccurrence = nil
        startManagedInitialOccurrence(
            configuration: owner.configuration,
            boundaryConfiguration: nextBoundaryConfiguration,
            sceneIdentifier: sceneIdentifier,
            state: state,
            admission: admission,
            allowsSameGenerationRemount: allowsSameGenerationRemount,
            process: process
        )
        return managedInitialOccurrence == nil ? .rejectStale : .handled

        }()
    }

    /// Protects a provisional destination from lifecycle callbacks emitted by
    /// the non-current boundary that lent it scene proof. A refreshed donor may
    /// update its own dormant bookkeeping, but it cannot replace or stop the
    /// visible destination before the accepted boundary materializes.
    func retainsManagedInitialOccurrence(
        for boundaryConfiguration: RUMViewTrackingState.Configuration,
        state: RUMViewTrackingState,
        attachment: RUMViewTrackingState.Attachment? = nil
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard admits(admission) else { return false }
        pruneExpiredRecords()
        return {

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

        }()
    }

    /// Balances source-managed initial or retained occurrences if the navigation
    /// container itself is removed. This is intentionally called from an outer
    /// attachment reader rather than the root content's `onDisappear`, which is
    /// also expected during an ordinary push.
    @discardableResult
    func cancelNavigationOwnedOccurrences(
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> [RUMViewTrackingState.Transition] {
        guard admits(admission) else { return [] }
        pruneExpiredRecords()
        return {

        var stoppedIdentities: Set<String> = []
        var transitions: [RUMViewTrackingState.Transition] = []
        if let owner = managedInitialOccurrence {
            transitions += stopManagedInitialOccurrence(
                owner,
                admission: admission,
                stoppedIdentities: &stoppedIdentities
            )
        }
        if let pendingRevealedRoute {
            transitions += stopNavigationOwnedOccurrence(
                state: pendingRevealedRoute.state,
                configuration: pendingRevealedRoute.configuration,
                sceneIdentifier: pendingRevealedRoute.sceneIdentifier,
                admission: admission,
                stoppedIdentities: &stoppedIdentities
            )
        }
        managedInitialOccurrence = nil
        pendingRevealedRoute = nil
        requiresInitialBootstrap = false
        awaitsCommittedRevealConfiguration = false
        return transitions

        }()
    }

    /// Mirrors scene-stack teardown without publishing a duplicate stop. The
    /// views handler owns the disconnect command; this only releases the
    /// container's stale lease so another scene can become authoritative.
    func sceneDidDisconnect(_ sceneIdentifier: RUMSceneIdentifier,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

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

        }()
    }

    func reconcileOwnerState(_ state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

        guard
            let owner = managedInitialOccurrence,
            owner.state === state,
            state.activeLifecycleGeneration == nil
        else {
            return
        }
        managedInitialOccurrence = nil

        }()
    }

    func isAcceptedBoundary(
        _ configuration: RUMViewTrackingState.Configuration
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard admits(admission) else { return false }
        pruneExpiredRecords()
        return {

        matchesAcceptedDestination(configuration, admission: admission)

        }()
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
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> CandidateDisposition {
        guard admits(admission) else { return .rejectStale }
        pruneExpiredRecords()
        return {

        guard candidateConfiguration.isCurrentDestination else {
            return .recordDormant
        }
        guard
            let acceptedDestinationConfiguration,
            matchesAcceptedDestination(candidateConfiguration, admission: admission),
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

        }()
    }

    fileprivate func register(
        _ registration: RUMSwiftUINavigationOccurrenceRegistration,
        callbackEpoch: UInt64
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

        registrations.removeAll {
            $0.registration == nil || $0.registration === registration
        }
        registrations.append(
            WeakRegistration(
                registration: registration,
                callbackEpoch: callbackEpoch
            )
        )

        }()
    }

    fileprivate func unregister(
        _ registration: RUMSwiftUINavigationOccurrenceRegistration,
        expectedCallbackEpoch: UInt64
    ) {
        registrations.removeAll {
            $0.registration == nil ||
                ($0.registration === registration && $0.callbackEpoch == expectedCallbackEpoch)
        }
    }

    /// Reveals a route retained below the current navigation destination. A
    /// registration may have published an earlier occurrence or may only have
    /// retained materialization and scene proof while it was hidden.
    @discardableResult
    func revealRetainedRoute(
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard admits(admission) else { return false }
        pruneExpiredRecords()
        return {

        registrations.removeAll { $0.registration == nil }
        clearPendingRevealedRoute(admission: admission)
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

        }()
    }

    /// Lets a newly mounted SwiftUI subtree take ownership of a view occurrence
    /// that was already published by the navigation-owned source.
    func consumeRevealedRoute(
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        into state: RUMViewTrackingState
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard admits(admission) else { return false }
        pruneExpiredRecords()
        return {

        consumePendingRevealedRoute(
            configuration: configuration,
            sceneIdentifier: sceneIdentifier,
            into: state,
            admission: admission
        ) == .handled

        }()
    }

    private func matchesAcceptedDestination(
        _ configuration: RUMViewTrackingState.Configuration
    ,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard admits(admission) else { return false }
        pruneExpiredRecords()
        return {

        acceptedDestinationIdentity == DestinationIdentity(
            occurrenceKey: configuration.occurrenceKey,
            bindingGeneration: configuration.bindingGeneration
        )

        }()
    }

    private func startManagedInitialOccurrence(
        configuration: RUMViewTrackingState.Configuration,
        boundaryConfiguration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission,
        allowsSameGenerationRemount: Bool = false,
        process: @MainActor (
            RUMViewTrackingState.Configuration,
            RUMSceneIdentifier
        ) -> Void
    ) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

        if state.activeLifecycleGeneration == nil, state.needsReaderRemount {
            let transitions = state.mountCurrentNavigationDestinationAfterSceneDisconnect(
                in: sceneIdentifier,
                configuration: configuration
            )
            RUMSwiftUIViewTransitionPublisher.publish(
                transitions,
                state: state,
                fallback: configuration.descriptor,
                admission: admission
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
                admission: admission
            )
        } else {
            process(configuration, sceneIdentifier)
        }
        guard admitsRecord(state.admission, state: state) else { return }
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

        }()
    }

    @discardableResult
    private func stopManagedInitialOccurrence(
        _ owner: ManagedInitialOccurrence,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> [RUMViewTrackingState.Transition] {
        guard admits(admission) else { return [] }
        pruneExpiredRecords()
        guard admitsRecord(owner.originalAdmission, state: owner.state) else { return [] }
        return {

        var stoppedIdentities: Set<String> = []
        return stopManagedInitialOccurrence(
            owner,
            admission: admission,
            stoppedIdentities: &stoppedIdentities
        )

        }()
    }

    private func stopManagedInitialOccurrence(
        _ owner: ManagedInitialOccurrence,
        admission: RUMSwiftUIViewCallbackAdmission,
        stoppedIdentities: inout Set<String>
    ) -> [RUMViewTrackingState.Transition] {
        guard admits(admission) else { return [] }
        pruneExpiredRecords()
        guard admitsRecord(owner.originalAdmission, state: owner.state) else { return [] }
        return {

        stopNavigationOwnedOccurrence(
            state: owner.state,
            configuration: owner.state.configuration ?? owner.configuration,
            sceneIdentifier: owner.sceneIdentifier,
            admission: admission,
            stoppedIdentities: &stoppedIdentities
        )

        }()
    }

    private func stopNavigationOwnedOccurrence(
        state: RUMViewTrackingState,
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        admission: RUMSwiftUIViewCallbackAdmission,
        stoppedIdentities: inout Set<String>
    ) -> [RUMViewTrackingState.Transition] {
        guard admits(admission) else { return [] }
        pruneExpiredRecords()
        guard admitsRecord(state.admission, state: state) else { return [] }
        return {

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
            admission: admission
        )
        return transitions

        }()
    }

    private func consumePendingRevealedRoute(
        configuration: RUMViewTrackingState.Configuration,
        sceneIdentifier: RUMSceneIdentifier,
        into state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> CandidateDisposition? {
        guard admits(admission) else { return nil }
        pruneExpiredRecords()
        return {

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
                clearPendingRevealedRoute(admission: admission)
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
                admission: admission
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
                    admission: admission
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

        }()
    }

    private func clearPendingRevealedRoute(admission: RUMSwiftUIViewCallbackAdmission) {
        guard admits(admission) else { return }
        pruneExpiredRecords()
        return {

        guard let pendingRevealedRoute else {
            return
        }
        _ = pendingRevealedRoute.state.settleRetainedRouteHandoff(
            configuration: pendingRevealedRoute.configuration,
            sceneIdentifier: pendingRevealedRoute.sceneIdentifier
        )
        self.pendingRevealedRoute = nil

        }()
    }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

/// Retained route callbacks must not capture a modifier or its State storage.
/// The registration owns this context; its collaborators have independent lives.
@MainActor
internal final class RUMSwiftUINavigationOccurrenceContext {
    private weak var state: RUMViewTrackingState?
    private let admission: RUMSwiftUIViewCallbackAdmission
    private let fallback: RUMViewTrackingState.Configuration.Descriptor
    #if os(iOS)
    var transitionArbiter: RUMSwiftUIViewTransitionAdmission?
    #endif

    init(
        state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission,
        fallback: RUMViewTrackingState.Configuration.Descriptor
    ) {
        self.state = state
        self.admission = admission
        self.fallback = fallback
    }

    func process(configuration: RUMViewTrackingState.Configuration, sceneIdentifier: RUMSceneIdentifier) {
        guard admission.isValid, admission.admits(sceneIdentifier: sceneIdentifier), let state, state.admission?.matches(admission) == true else {
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
        guard admission.isValid, let state, state.admission?.matches(admission) == true else {
            return
        }
        RUMSwiftUIViewTransitionPublisher.publish(transitions, state: state, fallback: fallback, admission: admission)
    }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

/// Stable state retained by one keyed modifier while its hidden scene reader
/// callbacks are rebound to newer SwiftUI values.
@MainActor
internal final class RUMSwiftUINavigationOccurrenceRegistration {
    typealias Process = @MainActor (
        RUMViewTrackingState.Configuration,
        RUMSceneIdentifier
    ) -> Void

    private weak var source: RUMSwiftUINavigationOccurrenceSource?
    private weak var state: RUMViewTrackingState?
    private var configuration: RUMViewTrackingState.Configuration?
    private var attachment: RUMViewTrackingState.Attachment = .detached
    private var process: Process?
    private var admission: RUMSwiftUIViewCallbackAdmission?
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
        process: @escaping Process,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard source.admits(admission), state.admission?.matches(admission) == true else { return }
        if let current = state.configuration {
            guard configuration.bindingGeneration >= current.bindingGeneration,
                  configuration.bindingGeneration != current.bindingGeneration
                    || configuration.occurrenceKey == current.occurrenceKey else { return }
        }
        unregisterSourceBinding(
            expectedCallbackEpoch: callbackEpoch,
            expectedSource: self.source,
            expectedState: self.state
        )
        self.admission = admission
        self.source = source
        self.state = state
        self.configuration = configuration
        self.attachment = attachment
        self.process = process
        source.register(self, callbackEpoch: callbackEpoch, admission: admission)
    }

    /// Retained, hidden routes stay registered. Cancel only when replacing or
    /// removing the binding; final owner destruction releases the callback.
    func cancel() {
        // Holder cancellation has already retired this Session's eligibility fence.
        unregisterSourceBinding(
            expectedCallbackEpoch: callbackEpoch, expectedSource: source, expectedState: state
        )
    }

    /// Same-Session source bookkeeping; this does not replace or reactivate the Session fence.
    private func unregisterSourceBinding(
        expectedCallbackEpoch: UInt64,
        expectedSource: RUMSwiftUINavigationOccurrenceSource?,
        expectedState: RUMViewTrackingState?
    ) {
        guard callbackEpoch == expectedCallbackEpoch,
              source === expectedSource, state === expectedState else { return }
        source?.unregister(self, expectedCallbackEpoch: expectedCallbackEpoch)
        callbackEpoch &+= 1
        source = nil
        state = nil
        configuration = nil
        attachment = .detached
        process = nil
        admission = nil
    }

    fileprivate func revealRetainedRoute(
        from source: RUMSwiftUINavigationOccurrenceSource,
        occurrenceKey: RUMViewOccurrenceKey,
        bindingGeneration: UInt64,
        expectedCallbackEpoch: UInt64
    ) -> RUMSceneIdentifier? {
        guard
            admission?.isValid == true,
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
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)

/// Applies reconciled SwiftUI lifecycle transitions to the scene-aware view
/// handler. Keyed occurrences own an immutable descriptor snapshot; legacy
/// transitions use the modifier's existing descriptor for compatibility.
internal enum RUMSwiftUIViewTransitionPublisher {
    @MainActor
    static func publish(
        _ transitions: [RUMViewTrackingState.Transition],
        state: RUMViewTrackingState,
        fallback: RUMViewTrackingState.Configuration.Descriptor,
        admission: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admission.isValid,
              let original = state.admission, original.isValid,
              original.binding.epoch == admission.binding.epoch,
              original.binding.lifetime === admission.binding.lifetime,
              let foundation = original.foundation else { return }
        for transition in transitions {
            guard original.isValid else { return }
            switch transition {
            case .start(let identity, let sceneIdentifier):
                guard let sceneIdentifier, original.admits(sceneIdentifier: sceneIdentifier) else { continue }
                let descriptor = state.descriptor(for: identity) ?? fallback
                foundation.appear(
                    identity: identity, name: descriptor.name, path: descriptor.path,
                    attributes: descriptor.attributes, sceneIdentifier: sceneIdentifier,
                    binding: original.binding
                )
            case .stop(let identity, let sceneIdentifier):
                guard let sceneIdentifier, original.admits(sceneIdentifier: sceneIdentifier) else { continue }
                foundation.disappear(identity: identity, sceneIdentifier: sceneIdentifier, binding: original.binding)
            case .replace(let oldIdentity, let newIdentity, let sceneIdentifier):
                guard let sceneIdentifier, original.admits(sceneIdentifier: sceneIdentifier) else { continue }
                let descriptor = state.descriptor(for: newIdentity) ?? fallback
                foundation.replace(
                    identity: oldIdentity, newIdentity: newIdentity,
                    name: descriptor.name, path: descriptor.path,
                    attributes: descriptor.attributes, sceneIdentifier: sceneIdentifier,
                    binding: original.binding
                )
            }
        }
    }
}
#endif // os(iOS)

#endif // canImport(SwiftUI)
