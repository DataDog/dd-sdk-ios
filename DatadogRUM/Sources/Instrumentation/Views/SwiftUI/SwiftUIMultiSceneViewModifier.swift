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

@available(iOS 17.0, *)
private struct RUMSceneIdentifierEnvironmentKey: UITraitBridgedEnvironmentKey {
    static let defaultValue: String? = nil

    static func read(from traitCollection: UITraitCollection) -> String? {
        traitCollection[RUMSceneIdentifierTrait.self]
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: String?) {
        mutableTraits[RUMSceneIdentifierTrait.self] = value
    }
}
#endif // os(iOS)

#if os(iOS)

@available(iOS 17.0, *)
private extension EnvironmentValues {
    var rumSceneIdentifier: String? {
        get { self[RUMSceneIdentifierEnvironmentKey.self] }
        set { self[RUMSceneIdentifierEnvironmentKey.self] = newValue }
    }
}
#endif // os(iOS)

#if os(iOS)
private struct RUMMultiSceneViewModifier: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.modifier(
                RUMTraitBackedMultiSceneViewModifier(
                    foundationBinding: foundationBinding,
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
                    foundationBinding: foundationBinding,
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
#endif // os(iOS)

#if os(iOS)

@available(iOS 17.0, *)
@MainActor
private struct RUMTraitBackedMultiSceneViewModifier: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
    let startsOnInitialMount: Bool
    @State private var trackingEpoch = RUMSwiftUIViewTrackingEpoch()

    @ViewBuilder
    func body(content: Content) -> some View {
        if let callback = trackingEpoch.enter(foundationBinding),
           let admission = RUMSwiftUIViewCallbackAdmission(holder: trackingEpoch, callback: callback) {
            content.modifier(
                RUMTraitBackedMultiSceneViewModifierCallback(
                    foundationBinding: foundationBinding,
                    name: name, path: path, attributes: attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: navigationOccurrenceSource,
                    startsOnInitialMount: startsOnInitialMount,
                    admission: admission
                )
            )
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
@MainActor
private struct RUMTraitBackedMultiSceneViewModifierCallback: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
    let startsOnInitialMount: Bool

    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    let admission: RUMSwiftUIViewCallbackAdmission

    func body(content: Content) -> some View {
        reconcileDormantNavigationBoundaryFromEnvironmentTrait()
        let onInitialMount: (@MainActor (RUMSceneIdentifier) -> Void)?
        if startsOnInitialMount {
            onInitialMount = { sceneIdentifier in
                initialMount(in: sceneIdentifier)
            }
        } else {
            onInitialMount = nil
        }
        let onMount: (@MainActor (RUMSceneIdentifier) -> Void)?
        if startsOnInitialMount {
            onMount = { sceneIdentifier in
                mount(in: sceneIdentifier)
            }
        } else {
            onMount = nil
        }
        let onReconcile: (@MainActor (RUMViewTrackingState.Attachment) -> Void)?
        if configuration == nil {
            onReconcile = nil
        } else {
            onReconcile = { attachment in
                update(attachment: attachment, allowsDormantBoundaryPromotion: true)
                rebindNavigationOccurrenceSource(attachment: attachment)
            }
        }
        return content
            .background(
                RUMSceneIdentifierReader(
                    admission: admission,
                    applicationSupportsMultipleScenes: true,
                    initialSceneIdentifier: initialSceneIdentifier,
                    onCreate: { observer in
                        register(observer: observer)
                    },
                    onInitialMount: onInitialMount,
                    onMount: onMount,
                    onReconcile: onReconcile,
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
                _ = admission.withSession { session in
                    if !session.didReceiveInitialSceneIdentifier {
                        session.didReceiveInitialSceneIdentifier = true
                        appear()
                    }
                }
            }
            .onAppear {
                update(attachment: attachment(for: sceneIdentifier))
                appear()
            }
            .onDisappear(perform: admission.disappearanceCallback {
                disappear()
            })
    }

    /// iOS 27 may reuse the speculative route's modifier state for the route
    /// accepted by a canonicalizing Binding. Reconcile during body evaluation so
    /// the accepted RUM view is queued before customer `onAppear` and immediate
    /// task work. The source and state retain the scene/generation fences; this
    /// trait-backed path cannot migrate or recover a disconnected boundary.
    private func reconcileDormantNavigationBoundaryFromEnvironmentTrait() {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
                , admission: admission)
        else {
            return
        }
        promoteDormantNavigationBoundary(
            from: expected,
            to: accepted,
            in: sceneIdentifier
        )

        }
    }

    private var initialSceneIdentifier: RUMSceneIdentifier? {
        guard startsOnInitialMount else {
            return nil
        }
        return sceneIdentifier.map { RUMSceneIdentifier(rawValue: $0) }
    }

    private func register(observer: RUMSceneIdentifierReader.ObserverView) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        #if os(iOS)
        transitionArbiter?.register(
            observer: observer,
            for: trackingState,
            navigationOccurrenceSource: navigationOccurrenceSource
        )
        admission.foundation?.registerAuthority(
            observer: observer,
            trackingState: trackingState,
            admission: admission
        )
        #endif

        }
    }

    private func mount(in sceneIdentifier: RUMSceneIdentifier) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
    }

    private func initialMount(in sceneIdentifier: RUMSceneIdentifier) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
    }

    private func update(
        attachment: RUMViewTrackingState.Attachment,
        allowsDormantBoundaryPromotion: Bool = false
    ) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        if let configuration {
            if navigationOccurrenceSource?.retainsManagedInitialOccurrence(
                for: configuration,
                state: trackingState,
                attachment: attachment
            , admission: admission) == true {
                rebindNavigationOccurrenceSource(attachment: attachment)
                return
            }
            if
                case .detached = attachment,
                allowsDormantBoundaryPromotion,
                navigationOccurrenceSource?.isAcceptedBoundary(configuration, admission: admission) == true,
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
    }

    private func appear() {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
            } else if navigationOccurrenceSource?.isAcceptedBoundary(configuration, admission: admission) == false {
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
    }

    private func disappear() {
        #if DD_SDK_COMPILED_FOR_TESTING
        admission.recordLifecycleObservation("trait-disappear-entry")
        #endif
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration
            #if DD_SDK_COMPILED_FOR_TESTING
            admission.recordLifecycleObservation("trait-disappear-admitted", state: trackingState)
            #endif

        if let configuration {
            if navigationOccurrenceSource?.retainsManagedInitialOccurrence(
                for: configuration,
                state: trackingState
            , admission: admission) == true {
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
            #if DD_SDK_COMPILED_FOR_TESTING
            admission.recordLifecycleObservation("trait-disappear-arbiter", state: trackingState)
            #endif
            transitionArbiter.process(.disappear, state: trackingState, send: apply)
            return
        }
        #endif
        #if DD_SDK_COMPILED_FOR_TESTING
        admission.recordLifecycleObservation("trait-disappear-direct", state: trackingState)
        #endif
        apply(trackingState.disappear())

        }
    }

    private func rebindNavigationOccurrenceSource(
        attachment: RUMViewTrackingState.Attachment
    ) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        guard let configuration, let navigationOccurrenceSource else {
            navigationOccurrenceRegistration.cancel()
            return
        }
        let context = RUMSwiftUINavigationOccurrenceContext(
            state: trackingState,
            admission: admission,
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
            process: context.process,
            admission: admission
        )

        }
    }

    private func resolveNavigationCandidate(
        _ configuration: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        isReaderMount: Bool = false,
        allowsDormantBoundaryPromotion: Bool = false
    ) -> RUMSwiftUINavigationOccurrenceSource.CandidateDisposition {
        return admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        guard let navigationOccurrenceSource else {
            return .allowOrdinaryMount
        }
        return navigationOccurrenceSource.resolveCandidate(
            candidateConfiguration: configuration,
            sceneIdentifier: sceneIdentifier,
            state: trackingState,
            isReaderMount: isReaderMount,
            allowsDormantBoundaryPromotion: allowsDormantBoundaryPromotion,
            admission: admission
        ) { initialConfiguration, sceneIdentifier in
            apply(
                trackingState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: initialConfiguration
                )
            )
        }

        } ?? .rejectStale
    }

    private func promoteDormantNavigationBoundary(
        from expected: RUMViewTrackingState.Configuration,
        to accepted: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
    }

    private func settleDormantNavigationBoundary(
        from expected: RUMViewTrackingState.Configuration,
        to accepted: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier
    ) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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
    }

    #if os(iOS)
    private var transitionArbiter: RUMSwiftUIViewTransitionAdmission? {
        guard startsOnInitialMount else {
            return nil
        }
        return admission.foundation?.makeTransitionAdmission(for: admission)
    }
    #endif

    private func apply(_ transitions: [RUMViewTrackingState.Transition]) {
        #if DD_SDK_COMPILED_FOR_TESTING
        admission.recordLifecycleObservation("trait-apply-entry", transitions: transitions)
        #endif
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration
            #if DD_SDK_COMPILED_FOR_TESTING
            admission.recordLifecycleObservation(
                "trait-publisher-call", state: trackingState, transitions: transitions
            )
            #endif

        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: trackingState,
            fallback: .init(name: name, path: path, attributes: attributes),
            admission: admission
        )
        navigationOccurrenceSource?.reconcileOwnerState(trackingState, admission: admission)

        }
    }

    private func recordDormantNavigationBoundaryFromReaderMount(
        attachment: RUMViewTrackingState.Attachment
    ) -> Bool {
        return admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

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

        } ?? false
    }

    private func attachment(for sceneIdentifier: String?) -> RUMViewTrackingState.Attachment {
        return admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        return sceneIdentifier
            .map { .attached(RUMSceneIdentifier(rawValue: $0)) }
            ?? .detached

        } ?? .detached
    }
}
#endif // os(iOS)

#if os(iOS)

@MainActor
private struct RUMAttachmentBackedMultiSceneViewModifier: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
    @State private var trackingEpoch = RUMSwiftUIViewTrackingEpoch()

    @ViewBuilder
    func body(content: Content) -> some View {
        if let callback = trackingEpoch.enter(foundationBinding),
           let admission = RUMSwiftUIViewCallbackAdmission(holder: trackingEpoch, callback: callback) {
            content.modifier(
                RUMAttachmentBackedMultiSceneViewModifierCallback(
                    foundationBinding: foundationBinding,
                    name: name, path: path, attributes: attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: navigationOccurrenceSource,
                    admission: admission
                )
            )
        } else {
            content
        }
    }
}

@MainActor
private struct RUMAttachmentBackedMultiSceneViewModifierCallback: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    let name: String
    let path: String
    let attributes: [AttributeKey: AttributeValue]
    let configuration: RUMViewTrackingState.Configuration?
    let navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?

    let admission: RUMSwiftUIViewCallbackAdmission

    func body(content: Content) -> some View {
        let onReconcile: (@MainActor (RUMViewTrackingState.Attachment) -> Void)?
        if configuration == nil {
            onReconcile = nil
        } else {
            onReconcile = { attachment in
                update(attachment: attachment)
                rebindNavigationOccurrenceSource(attachment: attachment)
            }
        }
        return content
            .background(
                RUMSceneIdentifierReader(
                    admission: admission,
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        register(observer: observer)
                    },
                    onReconcile: onReconcile,
                    onChange: { attachment in
                        update(attachment: attachment)
                        rebindNavigationOccurrenceSource(attachment: attachment)
                    }
                )
            )
            .onAppear {
                _ = admission.withSession { session in
                    let trackingState = session.trackingState
                    if let configuration {
                        apply(trackingState.appear(configuration: configuration))
                    } else {
                        apply(trackingState.appear())
                    }
                }
            }
            .onDisappear {
                _ = admission.withSession { session in
                    let trackingState = session.trackingState
                    if let configuration {
                        apply(trackingState.disappear(configuration: configuration))
                    } else {
                        apply(trackingState.disappear())
                    }
                }
            }
    }

    private func register(observer: RUMSceneIdentifierReader.ObserverView) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        #if os(iOS)
        admission.foundation?.registerAuthority(
            observer: observer,
            trackingState: trackingState,
            admission: admission
        )
        #endif

        }
    }

    private func update(attachment: RUMViewTrackingState.Attachment) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        if let configuration {
            if
                case .attached(let sceneIdentifier?) = attachment,
                consumeRevealedRoute(configuration, in: sceneIdentifier, admission: admission) {
                return
            }
            apply(trackingState.update(configuration: configuration, attachment: attachment))
        } else {
            apply(trackingState.update(attachment: attachment))
        }

        }
    }

    private func rebindNavigationOccurrenceSource(
        attachment: RUMViewTrackingState.Attachment
    ) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        guard let configuration, let navigationOccurrenceSource else {
            navigationOccurrenceRegistration.cancel()
            return
        }
        let context = RUMSwiftUINavigationOccurrenceContext(
            state: trackingState,
            admission: admission,
            fallback: configuration.descriptor
        )
        navigationOccurrenceRegistration.rebind(
            to: navigationOccurrenceSource,
            state: trackingState,
            configuration: configuration,
            attachment: attachment,
            process: context.process,
            admission: admission
        )

        }
    }

    private func consumeRevealedRoute(
        _ configuration: RUMViewTrackingState.Configuration,
        in sceneIdentifier: RUMSceneIdentifier,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        return admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        return navigationOccurrenceSource?.consumeRevealedRoute(
            configuration: configuration,
            sceneIdentifier: sceneIdentifier,
            into: trackingState
        , admission: admission) == true

        } ?? false
    }

    private func apply(_ transitions: [RUMViewTrackingState.Transition]) {
        _ = admission.withSession { session in
            let trackingState = session.trackingState
            let navigationOccurrenceRegistration = session.navigationRegistration

        RUMSwiftUIViewTransitionPublisher.publish(
            transitions,
            state: trackingState,
            fallback: .init(name: name, path: path, attributes: attributes),
            admission: admission
        )

        }
    }
}
#endif // os(iOS)

#if os(iOS)
/// Presentation half of semantic navigation ownership. The router publishes
/// the RUM occurrence, while this modifier keeps automatic discovery out of
/// the presented platform subtree until UIKit finishes removing it.
@MainActor
private struct RUMAutomaticViewSuppressionModifier: SwiftUI.ViewModifier {
    let foundationBinding: RUMSwiftUIViewFoundationBinding
    @State private var trackingEpoch = RUMSwiftUIViewTrackingEpoch()

    @ViewBuilder
    func body(content: Content) -> some View {
        if let callback = trackingEpoch.enter(foundationBinding),
           let admission = RUMSwiftUIViewCallbackAdmission(holder: trackingEpoch, callback: callback) {
            content.background(
                RUMSceneIdentifierReader(
                    admission: admission,
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        _ = admission.withSession { session in
                            admission.foundation?.registerSuppression(
                                observer: observer,
                                suppressionState: session.suppressionState,
                                admission: admission
                            )
                        }
                    },
                    onChange: { _ in }
                )
            )
            .onAppear { _ = admission.withSession { $0.suppressionState.appear() } }
            .onDisappear { _ = admission.withSession { $0.suppressionState.disappear() } }
        } else { content }
    }
}
#endif // os(iOS)

#endif // canImport(SwiftUI)

#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import DatadogInternal

// Colocate this factory with the complete private On modifier declarations.
@available(iOS 27.0, *)
@MainActor
@ViewBuilder
internal func rumMultiSceneTrackedContent<Content: SwiftUI.View>(
    _ content: Content,
    binding: RUMSwiftUIViewFoundationBinding,
    name: String,
    path: String,
    attributes: [AttributeKey: AttributeValue],
    configuration: RUMViewTrackingState.Configuration?,
    navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
) -> some View {
    if binding.isValid {
        content.modifier(
            RUMTraitBackedMultiSceneViewModifier(
                foundationBinding: binding,
                name: name,
                path: path,
                attributes: attributes,
                configuration: configuration,
                navigationOccurrenceSource: navigationOccurrenceSource,
                startsOnInitialMount: true
            )
        )
    } else {
        content
    }
}
#endif
