/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// Original keyed transition bodies retained; every deferred state keeps its original admission.
#if canImport(SwiftUI)
import Combine
import SwiftUI
import DatadogInternal
#if os(iOS)
import UIKit
#endif

#if os(iOS)
#if os(iOS)
internal protocol RUMSwiftUITransitionCoordinating: AnyObject {
    @MainActor var identity: ObjectIdentifier { get }
    @MainActor var initiallyInteractive: Bool { get }

    @MainActor
    func registerCompletion(_ completion: @escaping (_ isCancelled: Bool) -> Void) -> Bool
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

private final class RUMUIKitSwiftUITransitionCoordinator: RUMSwiftUITransitionCoordinating {
    private let coordinator: any UIViewControllerTransitionCoordinator

    @MainActor
    var identity: ObjectIdentifier {
        ObjectIdentifier(coordinator as AnyObject)
    }

    @MainActor
    var initiallyInteractive: Bool {
        coordinator.initiallyInteractive
    }

    init(coordinator: any UIViewControllerTransitionCoordinator) {
        self.coordinator = coordinator
    }

    @MainActor
    func registerCompletion(_ completion: @escaping (_ isCancelled: Bool) -> Void) -> Bool {
        coordinator.animate(alongsideTransition: nil) { context in
            completion(context.isCancelled)
        }
    }
}
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

/// Finds the interactive UIKit transition associated with one explicitly
/// tracked SwiftUI view. An attached reader is the strongest signal because it
/// identifies that view's hosting controller. A scene-root lookup is only used
/// while a newly created reader has not joined the responder hierarchy yet.
///
/// The fallback is intentionally scoped to the matching `UIWindowScene`: a
/// transition in another window must never delay this view's lifecycle.
internal struct RUMSwiftUITransitionCoordinatorProvider {
    typealias SceneViewControllers = @MainActor (RUMSceneIdentifier) -> [UIViewController]
    typealias ControllerCoordinator = @MainActor (UIViewController) -> (any RUMSwiftUITransitionCoordinating)?

    private let sceneViewControllers: SceneViewControllers
    private let controllerCoordinator: ControllerCoordinator

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    private func ancestorViewControllers(of viewController: UIViewController) -> [UIViewController] {
        var ancestors: [UIViewController] = []
        var parent = viewController.parent
        while let current = parent {
            ancestors.append(current)
            parent = current.parent
        }
        return ancestors
    }

    @MainActor
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
#endif // os(iOS)
#endif // os(iOS)

#if os(iOS)
#if os(iOS)

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

        @MainActor
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

    typealias CoordinatorProvider = @MainActor (
        _ sceneIdentifier: RUMSceneIdentifier,
        _ observers: [RUMSceneIdentifierReader.ObserverView]
    ) -> (any RUMSwiftUITransitionCoordinating)?

    private final class ObserverRegistration {
        weak var observer: RUMSceneIdentifierReader.ObserverView?
        weak var state: RUMViewTrackingState?
        weak var navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
        let admission: RUMSwiftUIViewCallbackAdmission?

        @MainActor
        init(
            observer: RUMSceneIdentifierReader.ObserverView,
            state: RUMViewTrackingState,
            navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource?
        ) {
            self.observer = observer
            self.state = state
            self.navigationOccurrenceSource = navigationOccurrenceSource
            self.admission = state.admission
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
        let admission: RUMSwiftUIViewCallbackAdmission?
        let sequence: Int
        var baseRevision: UInt64
        let baseIsAppeared: Bool
        var send: @MainActor ([RUMViewTrackingState.Transition]) -> Void
        var isProvisional: Bool
        var configuration: RUMViewTrackingState.Configuration?
        var attachment: RUMViewTrackingState.Attachment?
        var isAppeared: Bool?
        var allowsRemount = false
        var containsReaderMount = false
        var dormantBoundaryResolution: DormantBoundaryResolution?

        @MainActor
        init(
            state: RUMViewTrackingState,
            sequence: Int,
            isProvisional: Bool,
            send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void
        ) {
            self.state = state
            self.admission = state.admission
            self.sequence = sequence
            self.baseRevision = state.revision
            self.baseIsAppeared = state.isAppeared
            self.isProvisional = isProvisional
            self.configuration = state.configuration
            self.send = send
        }

        @MainActor
        func merge(
            _ intent: Intent,
            send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void
        ) -> Bool {
            guard admission?.isValid == true, state.admission.map({ admission?.matches($0) == true }) == true else { return false }

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

        @MainActor
        func accepts(_ intent: Intent) -> Bool {
            guard admission?.isValid == true, state.admission.map({ admission?.matches($0) == true }) == true else { return false }

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

        @MainActor
        func rebaseAfterSceneDisconnect() {
            guard admission?.isValid == true, state.admission.map({ admission?.matches($0) == true }) == true else { return }

            baseRevision = state.revision
            isAppeared = isAppeared ?? baseIsAppeared
            allowsRemount = true
        }

        @MainActor
        func preserveDormantPromotionAfterSceneDisconnect() {
            guard admission?.isValid == true, state.admission.map({ admission?.matches($0) == true }) == true else { return }

            guard let dormantBoundaryResolution else {
                return
            }
            _ = state.preserveDormantNavigationPromotionAfterSceneDisconnect(
                from: dormantBoundaryResolution.expected,
                to: dormantBoundaryResolution.accepted
            )
        }

        @MainActor
        var needsReaderRemountRearm: Bool {
            guard admission?.isValid == true else { return false }
            return containsReaderMount && state.needsReaderRemount
        }

        @MainActor
        func commit() {
            guard let admission, admission.isValid,
                  state.admission.map({ admission.matches($0) }) == true else { return }
            let projectedScene: RUMSceneIdentifier?
            if case .attached(let scene) = attachment {
                projectedScene = scene
            } else {
                projectedScene = state.sceneIdentifier
            }
            if let projectedScene, !admission.admits(sceneIdentifier: projectedScene) { return }

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

        @MainActor
        func contains(state: RUMViewTrackingState) -> Bool {
            states[ObjectIdentifier(state)] != nil
        }

        @MainActor
        func merge(
            _ intent: Intent,
            state: RUMViewTrackingState,
            isProvisional: Bool,
            send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void
        ) {
            guard let admission = state.admission, admission.isValid else { return }
            let identity = ObjectIdentifier(state)
            if let existing = states[identity] {
                guard existing.admission?.matches(admission) == true,
                      existing.merge(intent, send: send) else {
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

        @MainActor
        func deferredState(for state: RUMViewTrackingState) -> DeferredState? {
            states[ObjectIdentifier(state)]
        }

        @MainActor
        func remove(state: RUMViewTrackingState) -> DeferredState? {
            states.removeValue(forKey: ObjectIdentifier(state))
        }

        @MainActor
        var trackingStates: [RUMViewTrackingState] {
            states.values.filter { $0.admission?.isValid == true }.map(\.state)
        }

        @MainActor
        func rebaseAfterSceneDisconnect(statesWithIdentities identities: Set<ObjectIdentifier>) {
            states.forEach { identity, state in
                if identities.contains(identity) {
                    state.rebaseAfterSceneDisconnect()
                }
            }
        }

        @MainActor
        func preserveDormantPromotionsAfterSceneDisconnect(
            statesWithIdentities identities: Set<ObjectIdentifier>
        ) {
            states.forEach { identity, state in
                if identities.contains(identity) {
                    state.preserveDormantPromotionAfterSceneDisconnect()
                }
            }
        }

        @MainActor
        var statesNeedingReaderRemountRearm: [RUMViewTrackingState] {
            states.values.compactMap { state in
                state.needsReaderRemountRearm ? state.state : nil
            }
        }

        @MainActor
        func remove(statesWithIdentities identities: Set<ObjectIdentifier>) {
            states = states.filter { identity, _ in
                !identities.contains(identity)
            }
        }

        @MainActor
        var isEmpty: Bool {
            states.isEmpty
        }

        @MainActor
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
    private let admitsCallbacks: @MainActor () -> Bool
    private var disconnectObserver: NSObjectProtocol?
    private var observerRegistrations: [ObjectIdentifier: ObserverRegistration] = [:]
    private var deferredTransitions: [TransitionKey: DeferredTransition] = [:]

    @MainActor
    convenience init(notificationCenter: NotificationCenter, admitsCallbacks: @escaping @MainActor () -> Bool) {
        let provider = RUMSwiftUITransitionCoordinatorProvider()
        self.init(notificationCenter: notificationCenter, admitsCallbacks: admitsCallbacks) { sceneIdentifier, observers in
            provider.coordinator(for: sceneIdentifier, observers: observers)
        }
    }

    @MainActor
    init(notificationCenter: NotificationCenter, admitsCallbacks: @escaping @MainActor () -> Bool, coordinatorProvider: @escaping CoordinatorProvider) {
        self.notificationCenter = notificationCenter
        self.coordinatorProvider = coordinatorProvider
        self.admitsCallbacks = admitsCallbacks
        disconnectObserver = notificationCenter.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Notification delivery is not actor proof. UIKit inspection occurs in owned main delivery.
            weak var scene = notification.object as? UIWindowScene
            DispatchQueue.main.async { [weak self, weak scene] in
                guard let self, self.admitsCallbacks(), let scene else { return }
                self.discard(sceneIdentifier: RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier))
            }
        }
    }

    deinit {
        if let disconnectObserver {
            notificationCenter.removeObserver(disconnectObserver)
        }
    }

    @MainActor
    func cancelPendingWithoutPublishing() {
        deferredTransitions.removeAll()
        observerRegistrations.removeAll()
    }

    @MainActor
    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        for state: RUMViewTrackingState,
        navigationOccurrenceSource: RUMSwiftUINavigationOccurrenceSource? = nil
    ) {
        guard admitsCallbacks() else { return }

        guard Thread.isMainThread, let admission = state.admission, admission.isValid,
              let scene = observer.currentSceneIdentifier, admission.admits(sceneIdentifier: scene) else { return }
        observerRegistrations[ObjectIdentifier(observer)] = ObserverRegistration(
            observer: observer,
            state: state,
            navigationOccurrenceSource: navigationOccurrenceSource
        )
    }

    @MainActor
    func process(
        _ intent: Intent,
        state: RUMViewTrackingState,
        send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void
    ) {
        guard admitsCallbacks() else { return }

        guard Thread.isMainThread, let admission = state.admission, admission.isValid else { return }

        if let scene = intent.sceneIdentifier ?? state.sceneIdentifier,
           !admission.admits(sceneIdentifier: scene) { return }
        guard (intent.sceneIdentifier ?? state.sceneIdentifier) != nil else { return }
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

        guard let sceneIdentifier = intent.sceneIdentifier ?? state.sceneIdentifier,
              admission.admits(sceneIdentifier: sceneIdentifier) else { return }

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
            DispatchQueue.main.async { [weak self] in
                guard let self, self.admitsCallbacks() else { return }
                self.resolve(
                    transitionKey: transitionKey,
                    expectedTransition: deferredTransition,
                    isCancelled: isCancelled
                )
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

    @MainActor
    func discard(sceneIdentifier: RUMSceneIdentifier) {
        guard admitsCallbacks() else { return }

        guard Thread.isMainThread else {
            return
        }

        var candidateStates: [ObjectIdentifier: RUMViewTrackingState] = [:]
        observerRegistrations.values.forEach { registration in
            guard registration.admission?.isValid == true, let state = registration.state else {
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

        var disconnectedSources: [ObjectIdentifier: (RUMSwiftUINavigationOccurrenceSource, RUMSwiftUIViewCallbackAdmission)] = [:]
        observerRegistrations.values.forEach { registration in
            guard
                registration.admission?.isValid == true,
                let source = registration.navigationOccurrenceSource,
                let state = registration.state,
                registration.admission?.isValid == true,
                let observer = registration.observer,
                observer.lastSceneIdentifier == sceneIdentifier
                    || invalidatedStateIdentities.contains(ObjectIdentifier(state))
            else {
                return
            }
            if let admission = registration.admission {
                disconnectedSources[ObjectIdentifier(source)] = (source, admission)
            }
        }
        disconnectedSources.values.forEach { source, admission in
            DispatchQueue.main.async { [weak source, weak admission] in
                guard let admission, admission.isValid else { return }
                source?.sceneDidDisconnect(sceneIdentifier, admission: admission)
            }
        }

        var disconnectedObserverIdentities: Set<ObjectIdentifier> = []
        observerRegistrations.forEach { observerIdentity, registration in
            guard
                registration.admission?.isValid == true,
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
                registration.admission?.isValid == true,
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

    @MainActor
    private func resolve(
        transitionKey: TransitionKey,
        expectedTransition: DeferredTransition,
        isCancelled: Bool
    ) {
        guard admitsCallbacks() else { return }

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

    @MainActor
    private func liveObservers(
        for state: RUMViewTrackingState,
        sceneIdentifier: RUMSceneIdentifier
    ) -> [RUMSceneIdentifierReader.ObserverView] {
        guard admitsCallbacks() else { return [] }

        observerRegistrations = observerRegistrations.filter { _, registration in
            registration.admission?.isValid == true && registration.observer != nil && registration.state != nil
        }
        return observerRegistrations.values.compactMap { registration in
            guard
                registration.admission?.isValid == true,
                registration.state === state,
                registration.admission?.isValid == true,
                let observer = registration.observer,
                observer.lastSceneIdentifier == nil
                    || observer.lastSceneIdentifier == sceneIdentifier
            else {
                return nil
            }
            return observer
        }
    }

    @MainActor
    private func rearmReaderMounts(
        for states: [RUMViewTrackingState],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        guard admitsCallbacks() else { return }

        let identities = Set(states.map(ObjectIdentifier.init))
        observerRegistrations.values.forEach { registration in
            guard
                registration.admission?.isValid == true,
                let observer = registration.observer,
                let state = registration.state,
                identities.contains(ObjectIdentifier(state))
            else {
                return
            }
            observer.markSceneDisconnected(sceneIdentifier)
        }
    }

    @MainActor
    private func deferredTransition(
        for state: RUMViewTrackingState
    ) -> (key: TransitionKey, transition: DeferredTransition)? {
        guard admitsCallbacks() else { return nil }

        let match = deferredTransitions.first { _, transition in
            transition.contains(state: state)
        }
        return match.map { (key: $0.key, transition: $0.value) }
    }

    @MainActor
    private func commitOutsidePendingTransition(
        _ intent: Intent,
        state: RUMViewTrackingState,
        pending: (key: TransitionKey, transition: DeferredTransition),
        send: @escaping @MainActor ([RUMViewTrackingState.Transition]) -> Void
    ) {
        guard admitsCallbacks() else { return }

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
#endif // os(iOS)
#endif // os(iOS)

#endif // canImport(SwiftUI)
