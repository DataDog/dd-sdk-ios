/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Combine
import SwiftUI
import UIKit
import DatadogInternal

/// Defers accepted-state observation until the original host is admitted.
@available(iOS 27.0, *)
@MainActor
internal enum RUMNavigationHostInput {
    case automatic
    case transitions(RUMNavigationTransitions)
    case observing(@MainActor (@escaping @MainActor () -> Bool) -> RUMNavigationObservedTransitions)
}

/// Tracks one admitted semantic container without changing its content identity.
@available(iOS 27.0, *)
@MainActor
internal struct RUMNavigationHost<Content: View>: View {
    private weak var core: DatadogCoreProtocol?
    private let input: RUMNavigationHostInput
    private let content: Content
    #if DD_SDK_COMPILED_FOR_TESTING
    private var testingOnHostUpdate:
        ((RUMSemanticNavigationHostState, RUMSwiftUIViewCallbackAdmission?,
          RUMSceneIdentifierReader.ObserverView?) -> Void)?
    #endif

    init(
        transitions: RUMNavigationTransitions,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.input = .transitions(transitions)
        self.content = content()
    }

    init(
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.input = .automatic
        self.content = content()
    }

    init<State, Updates: Publisher>(
        observing updates: Updates,
        destination: @MainActor @escaping (State) -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata = .automatic,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) where Updates.Output == State, Updates.Failure == Never {
        self.core = core
        self.input = .observing { acceptsDelivery in
            RUMNavigationObservedTransitions(
                updates: updates,
                acceptsDelivery: acceptsDelivery,
                destination: destination,
                metadata: metadata
            )
        }
        self.content = content()
    }

    #if compiler(>=6.4) && canImport(Observation)
    init(
        observingCurrentDestination: @MainActor @escaping () -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata = .automatic,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder content: () -> Content
    ) {
        self.core = core
        self.input = .observing { acceptsDelivery in
            RUMNavigationObservedTransitions(
                observingCurrentDestination: observingCurrentDestination,
                acceptsDelivery: acceptsDelivery,
                metadata: metadata
            )
        }
        self.content = content()
    }
    #endif

    #if DD_SDK_COMPILED_FOR_TESTING
    init(
        transitions: RUMNavigationTransitions,
        in core: DatadogCoreProtocol,
        testingOnHostUpdate: @escaping (
            RUMSemanticNavigationHostState, RUMSwiftUIViewCallbackAdmission?,
            RUMSceneIdentifierReader.ObserverView?
        ) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            transitions: transitions,
            in: core,
            content: content
        )
        self.testingOnHostUpdate = testingOnHostUpdate
    }

    func withTestingOnHostUpdate(
        _ callback: @escaping (
            RUMSemanticNavigationHostState, RUMSwiftUIViewCallbackAdmission?,
            RUMSceneIdentifierReader.ObserverView?
        ) -> Void
    ) -> Self {
        var copy = self
        copy.testingOnHostUpdate = callback
        return copy
    }
    #endif

    var body: some View {
        let binding: RUMSwiftUIViewFoundationBinding?
        if let feature = core?.get(feature: RUMFeature.self),
           feature.isMultiSceneTrackingEnabled {
            binding = feature.instrumentation.swiftUIViewFoundation?.makeBinding()
        } else {
            binding = nil
        }
        var modifier = RUMSemanticNavigationHostModifier(
            binding: binding,
            input: input
        )
        #if DD_SDK_COMPILED_FOR_TESTING
        modifier.testingOnHostUpdate = testingOnHostUpdate
        #endif
        return content.modifier(modifier)
    }
}

/// Keeps observation and accepted occurrences within the original host admission.
@available(iOS 27.0, *)
@MainActor
internal final class RUMSemanticNavigationHostState {
    private struct Occurrence {
        let generation: UInt64
        let identity: String
        let scene: RUMSceneIdentifier
    }

    private let hostIdentifier = UUID()
    private let trackingEpoch = RUMSwiftUIViewTrackingEpoch()
    private var registration: RUMSwiftUIViewTrackingEpoch.Callback?
    private var admission: RUMSwiftUIViewCallbackAdmission?
    private weak var observer: RUMSceneIdentifierReader.ObserverView?
    private weak var configuredTransitions: RUMNavigationTransitions?
    private(set) var selectedTransitions: RUMNavigationTransitions?
    private var observedTransitions: RUMNavigationObservedTransitions?
    private var configuredObservationFactory:
        (@MainActor (@escaping @MainActor () -> Bool) -> RUMNavigationObservedTransitions)?
    private var sourceConfigurationGeneration: UInt64 = 0
    private var isConfiguringObservation = false
    private var observationID: UUID?
    private var observationGeneration: UInt64 = 0
    private var attachmentGeneration: UInt64 = 0
    private var detachGeneration: UInt64 = 0
    private var attachment: RUMViewTrackingState.Attachment = .detached
    private var requiresReaderMount = false
    private var hasMounted = false
    private var latestSnapshot: RUMNavigationTransitions.Snapshot?
    private var activeOccurrence: Occurrence?
    private var isActivating = false

    #if DD_SDK_COMPILED_FOR_TESTING
    var currentIdentity: String? { activeOccurrence?.identity }
    #endif

    deinit {
        // The source retains a weak callback. Remove its token on main even if
        // an external owner releases this state from another thread.
        let source = selectedTransitions
        let observationID = observationID
        let observation = observedTransitions
        if source != nil || observation != nil {
            DispatchQueue.main.async {
                if let source, let observationID {
                    source.removeObserver(observationID)
                }
                observation?.stop()
            }
        }
    }

    func configure(
        transitions: RUMNavigationTransitions,
        binding: RUMSwiftUIViewFoundationBinding?
    ) -> RUMSwiftUIViewCallbackAdmission? {
        configure(input: .transitions(transitions), binding: binding)
    }

    func configure(
        input: RUMNavigationHostInput,
        binding: RUMSwiftUIViewFoundationBinding?
    ) -> RUMSwiftUIViewCallbackAdmission? {
        guard let binding else {
            if admission != nil {
                finish(stopOccurrence: true)
                configuredObservationFactory = nil
                if let registration {
                    trackingEpoch.retire(registration)
                }
                registration = nil
                admission = nil
            }
            return nil
        }
        guard binding.isValid else {
            if admission?.binding.epoch == binding.epoch,
               admission?.binding.lifetime === binding.lifetime {
                finish(stopOccurrence: false)
                configuredObservationFactory = nil
                _ = trackingEpoch.enter(binding)
                registration = nil
                admission = nil
            }
            return nil
        }
        if let current = admission,
           !current.isValid || current.binding.epoch != binding.epoch
            || current.binding.lifetime !== binding.lifetime {
            finish(stopOccurrence: current.isValid)
            configuredObservationFactory = nil
            admission = nil
        }
        if admission == nil {
            guard let callback = trackingEpoch.enter(binding),
                  let admitted = RUMSwiftUIViewCallbackAdmission(
                    holder: trackingEpoch,
                    callback: callback
                  ) else {
                return nil
            }
            admission = admitted
            registration = callback
            requiresReaderMount = hasMounted
        }
        if selectedTransitions == nil, observedTransitions == nil,
           configuredObservationFactory == nil, !isConfiguringObservation {
            switch input {
            case .automatic:
                configuredTransitions = nil
            case .transitions(let transitions):
                configuredTransitions = transitions
            case .observing(let makeObservation):
                configuredObservationFactory = makeObservation
            }
        }
        if !requiresReaderMount, let expected = admission,
           !prepareObservedTransitions(admission: expected) {
            return nil
        }
        return admission
    }

    private func prepareObservedTransitions(
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) -> Bool {
        guard let makeObservation = configuredObservationFactory else {
            return true
        }
        guard observedTransitions == nil else {
            return true
        }
        guard !isConfiguringObservation, admits(expected) else {
            return false
        }
        sourceConfigurationGeneration &+= 1
        let generation = sourceConfigurationGeneration
        isConfiguringObservation = true
        let observation = makeObservation { [weak self, weak expected] in
            guard let self, let expected else {
                return false
            }
            return self.sourceConfigurationGeneration == generation && self.admits(expected)
        }
        isConfiguringObservation = false
        guard sourceConfigurationGeneration == generation, admits(expected) else {
            observation.stop()
            return false
        }
        observedTransitions = observation
        configuredTransitions = observation.transitions
        return true
    }

    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected) else {
            return
        }
        self.observer = observer
        registerSuppression(admission: expected)
    }

    func reconcileInitialScene(
        _ scene: RUMSceneIdentifier,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard !requiresReaderMount, admits(expected), expected.admits(sceneIdentifier: scene) else {
            return
        }
        attach(
            to: scene,
            admission: expected
        )
    }

    func readerDidMount(
        in scene: RUMSceneIdentifier,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected), observer?.currentSceneIdentifier == scene,
              expected.admits(sceneIdentifier: scene) else {
            return
        }
        // A disconnected host may return without SwiftUI rebuilding its value.
        // Recreate only its pinned input, after this actual reader proves ownership.
        guard prepareObservedTransitions(admission: expected) else {
            return
        }
        requiresReaderMount = false
        attach(
            to: scene,
            admission: expected
        )
        registerSuppression(admission: expected)
    }

    func reconcile(
        attachment: RUMViewTrackingState.Attachment,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected) else {
            return
        }
        if case .attached(let scene?) = attachment {
            readerDidMount(
                in: scene,
                admission: expected
            )
            return
        }
        self.attachment = .detached
        detachGeneration &+= 1
        let generation = detachGeneration
        // Keep teardown alive for this single queue turn after SwiftUI releases
        // the removed reader and its state. The admission still owns no Core.
        DispatchQueue.main.async { [self, expected] in
            guard self.admits(expected),
                  generation == self.detachGeneration,
                  self.attachment == .detached else {
                return
            }
            self.finalDetach(admission: expected)
        }
    }

    func finalDetach(admission expected: RUMSwiftUIViewCallbackAdmission) {
        guard admits(expected) else {
            return
        }
        finish(stopOccurrence: true)
    }

    func sceneDidDisconnect(
        _ scene: UIScene,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        let identifier = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        if let current = observer?.window?.windowScene,
           current.session.persistentIdentifier == identifier.rawValue,
           current !== scene {
            return
        }
        sceneDidDisconnect(
            identifier,
            admission: expected
        )
    }

    func sceneDidDisconnect(
        _ scene: RUMSceneIdentifier,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected),
              sceneIdentifier == scene || activeOccurrence?.scene == scene else {
            return
        }
        observer?.markSceneDisconnected(scene)
        // The handler owns the scene's stop; this only releases local resources.
        finish(stopOccurrence: false)
    }

    private var sceneIdentifier: RUMSceneIdentifier? {
        guard case .attached(let scene?) = attachment else {
            return nil
        }
        return scene
    }

    private func admits(_ expected: RUMSwiftUIViewCallbackAdmission) -> Bool {
        expected.isValid && admission?.matches(expected) == true
    }

    private func attach(
        to scene: RUMSceneIdentifier,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected), expected.admits(sceneIdentifier: scene) else {
            return
        }
        detachGeneration &+= 1
        hasMounted = true
        if let activeOccurrence, activeOccurrence.scene != scene {
            self.activeOccurrence = nil
            _ = expected.foundation?.disappear(
                identity: activeOccurrence.identity,
                sceneIdentifier: activeOccurrence.scene,
                binding: expected.binding
            )
            attachmentGeneration &+= 1
        }
        attachment = .attached(scene)
        selectSourceIfNeeded(admission: expected)
        activateLatestSnapshot()
    }

    private func selectSourceIfNeeded(admission expected: RUMSwiftUIViewCallbackAdmission) {
        guard admits(expected), selectedTransitions == nil,
              let source = configuredTransitions else {
            return
        }
        selectedTransitions = source
        observationGeneration &+= 1
        let generation = observationGeneration
        let id = source.observe { [weak self, weak expected] snapshot in
            guard let self, let expected, self.observationGeneration == generation else {
                return
            }
            guard self.admits(expected) else {
                if self.admission === expected {
                    self.finish(stopOccurrence: false)
                }
                return
            }
            self.latestSnapshot = snapshot
            self.activateLatestSnapshot()
        }
        guard admits(expected), selectedTransitions === source,
              generation == observationGeneration else {
            source.removeObserver(id)
            return
        }
        observationID = id
    }

    private func activateLatestSnapshot() {
        guard !isActivating else {
            return
        }
        isActivating = true
        defer { isActivating = false }

        // Synchronous source reentrancy updates latestSnapshot. Complete one
        // accepted SDK operation before reconciling the newer destination.
        while let admission, admits(admission), !requiresReaderMount,
              let scene = sceneIdentifier, admission.admits(sceneIdentifier: scene),
              let snapshot = latestSnapshot, let foundation = admission.foundation {
            if activeOccurrence?.generation == snapshot.generation,
               activeOccurrence?.scene == scene {
                return
            }
            let generation = attachmentGeneration
            let identity = "rum-navigation-\(hostIdentifier)-\(generation)-\(snapshot.generation)"
            let destination = snapshot.destination
            let accepted: Bool
            if let previous = activeOccurrence {
                accepted = foundation.replace(
                    identity: previous.identity,
                    newIdentity: identity,
                    name: destination.name,
                    path: destination.path ?? destination.name,
                    attributes: destination.attributes,
                    sceneIdentifier: scene,
                    binding: admission.binding
                )
            } else {
                accepted = foundation.appear(
                    identity: identity,
                    name: destination.name,
                    path: destination.path ?? destination.name,
                    attributes: destination.attributes,
                    sceneIdentifier: scene,
                    binding: admission.binding
                )
            }
            guard accepted, admits(admission), generation == attachmentGeneration,
                  sceneIdentifier == scene else {
                return
            }
            activeOccurrence = .init(
                generation: snapshot.generation,
                identity: identity,
                scene: scene
            )
            _ = admission.withSession { $0.suppressionState.appear() }
            registerSuppression(admission: admission)
        }
    }

    private func registerSuppression(admission expected: RUMSwiftUIViewCallbackAdmission) {
        guard admits(expected), let observer else {
            return
        }
        _ = expected.withSession { session in
            expected.foundation?.registerSuppression(
                observer: observer,
                suppressionState: session.suppressionState,
                admission: expected
            )
        }
    }

    private func finish(stopOccurrence: Bool) {
        let previous = activeOccurrence
        let originalAdmission = admission
        let source = selectedTransitions
        let observation = observedTransitions
        let id = observationID
        observationGeneration &+= 1
        attachmentGeneration &+= 1
        detachGeneration &+= 1
        requiresReaderMount = true
        attachment = .detached
        activeOccurrence = nil
        latestSnapshot = nil
        selectedTransitions = nil
        if configuredObservationFactory != nil {
            configuredTransitions = nil
        }
        observedTransitions = nil
        sourceConfigurationGeneration &+= 1
        isConfiguringObservation = false
        observationID = nil
        _ = originalAdmission?.withSession { $0.suppressionState.disappear() }
        if let source, let id {
            source.removeObserver(id)
        }
        if stopOccurrence, let previous, let originalAdmission, admits(originalAdmission) {
            _ = originalAdmission.foundation?.disappear(
                identity: previous.identity,
                sceneIdentifier: previous.scene,
                binding: originalAdmission.binding
            )
        }
        observation?.stop()
    }
}

@available(iOS 27.0, *)
@MainActor
private struct RUMSemanticNavigationHostModifier: ViewModifier {
    let binding: RUMSwiftUIViewFoundationBinding?
    let input: RUMNavigationHostInput
    @State private var state = RUMSemanticNavigationHostState()
    @Environment(\.rumSceneIdentifier)
    private var sceneIdentifier
    #if DD_SDK_COMPILED_FOR_TESTING
    var testingOnHostUpdate:
        ((RUMSemanticNavigationHostState, RUMSwiftUIViewCallbackAdmission?,
          RUMSceneIdentifierReader.ObserverView?) -> Void)?
    #endif

    func body(content: Content) -> some View {
        let admission = state.configure(
            input: input,
            binding: binding
        )
        #if DD_SDK_COMPILED_FOR_TESTING
        testingOnHostUpdate?(state, admission, nil)
        #endif
        _ = admission.map { reconcileInitialScene(admission: $0) }
        // Only the SDK background changes across feature epochs. The customer's
        // content keeps the same structural identity on On, Off and NOP paths.
        return content.background {
            if let admission,
               let notificationCenter = admission.foundation?.sceneLifecycleNotificationCenter {
                RUMSceneIdentifierReader(
                    admission: admission,
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        state.register(
                            observer: observer,
                            admission: admission
                        )
                        #if DD_SDK_COMPILED_FOR_TESTING
                        testingOnHostUpdate?(state, admission, observer)
                        #endif
                    },
                    onMount: { scene in
                        state.readerDidMount(
                            in: scene,
                            admission: admission
                        )
                    },
                    onReconcile: { attachment in
                        state.reconcile(
                            attachment: attachment,
                            admission: admission
                        )
                    },
                    onChange: { attachment in
                        state.reconcile(
                            attachment: attachment,
                            admission: admission
                        )
                    }
                )
                .onReceive(notificationCenter.publisher(for: UIScene.didDisconnectNotification)) { [weak state = state, weak admission] notification in
                    guard let state, let admission, let scene = notification.object as? UIScene else {
                        return
                    }
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            state.sceneDidDisconnect(
                                scene,
                                admission: admission
                            )
                        }
                    } else {
                        DispatchQueue.main.async { [weak state, weak admission, weak scene] in
                            guard let state, let admission, let scene else {
                                return
                            }
                            state.sceneDidDisconnect(
                                scene,
                                admission: admission
                            )
                        }
                    }
                }
            }
        }
    }

    private func reconcileInitialScene(admission: RUMSwiftUIViewCallbackAdmission) {
        guard let sceneIdentifier else {
            return
        }
        state.reconcileInitialScene(
            RUMSceneIdentifier(rawValue: sceneIdentifier),
            admission: admission
        )
    }
}
/// Owns native destination builders while retaining the application's path binding.
@available(iOS 27.0, *)
@MainActor
internal struct RUMNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    private weak var core: DatadogCoreProtocol?
    private let path: Binding<[Route]>
    private let metadata: RUMNavigationMetadata
    private let root: Root
    private let destination: (Route) -> Destination
    @State private var state = RUMNativeNavigationState<Route>()
    #if DD_SDK_COMPILED_FOR_TESTING
    private var testingOnNativeUpdate: ((
        RUMNativeNavigationState<Route>, RUMSwiftUIViewCallbackAdmission?,
        RUMSceneIdentifierReader.ObserverView?, Binding<[Route]>
    ) -> Void)?

    func withTestingOnNativeUpdate(_ callback: @escaping (
        RUMNativeNavigationState<Route>, RUMSwiftUIViewCallbackAdmission?,
        RUMSceneIdentifierReader.ObserverView?, Binding<[Route]>
    ) -> Void) -> Self {
        var copy = self
        copy.testingOnNativeUpdate = callback
        return copy
    }
    #endif

    init(
        path: Binding<[Route]>,
        metadata: RUMNavigationMetadata = .automatic,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.core = core
        self.path = path
        self.metadata = metadata
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        let binding: RUMSwiftUIViewFoundationBinding?
        if let feature = core?.get(feature: RUMFeature.self), feature.isMultiSceneTrackingEnabled {
            binding = feature.instrumentation.swiftUIViewFoundation?.makeBinding()
        } else {
            binding = nil
        }
        let admission = state.configure(binding: binding)
        state.reconcile(acceptedPath: { path.wrappedValue }, metadata: metadata, admission: admission)
        #if DD_SDK_COMPILED_FOR_TESTING
        testingOnNativeUpdate?(state, admission, nil, forwardedPath)
        #endif
        return NavigationStack(path: forwardedPath) {
            RUMNativeNavigationBoundary<Route, Root>(
                route: nil, state: state, admission: admission, content: root
            )
            .navigationDestination(for: Route.self) { route in
                RUMNativeNavigationBoundary(
                    route: route, state: state, admission: admission, content: destination(route)
                )
            }
        }
        .background {
            if let admission,
               let center = admission.foundation?.sceneLifecycleNotificationCenter {
                RUMSceneIdentifierReader(
                    admission: admission,
                    applicationSupportsMultipleScenes: true,
                    onCreate: { observer in
                        state.register(observer: observer, admission: admission)
                        #if DD_SDK_COMPILED_FOR_TESTING
                        testingOnNativeUpdate?(state, admission, observer, forwardedPath)
                        #endif
                    },
                    onMount: { state.reconcile(attachment: .attached($0), admission: admission) },
                    onReconcile: { state.reconcile(attachment: $0, admission: admission) },
                    onChange: { state.reconcile(attachment: $0, admission: admission) }
                )
                .onReceive(center.publisher(for: UIScene.didDisconnectNotification)) { [weak state] notification in
                    guard let scene = notification.object as? UIScene else {
                        return
                    }
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            state?.sceneDidDisconnect(scene, admission: admission)
                        }
                    } else {
                        DispatchQueue.main.async { [weak state, weak scene] in
                            guard let scene else {
                                return
                            }
                            state?.sceneDidDisconnect(scene, admission: admission)
                        }
                    }
                }
            }
        }
    }

    private var forwardedPath: Binding<[Route]> {
        Binding(
            get: { path.wrappedValue },
            set: { proposal, transaction in
                let original = state.admission
                state.reconcile(
                    acceptedPath: {
                        path.transaction(transaction).wrappedValue = proposal
                        // A rejecting or normalizing setter owns the accepted value.
                        return path.wrappedValue
                    },
                    metadata: metadata,
                    admission: original
                )
            }
        )
    }
}

/// Keeps path claims separate from actual reader-proven destination materialization.
@available(iOS 27.0, *)
@MainActor
internal final class RUMNativeNavigationState<Route: Hashable> {
    private struct Position: Hashable {
        let container: UUID
        let slot: UUID
        let depth: Int
    }

    final class Claim {
        fileprivate var route: Route?
        fileprivate var depth: Int
        fileprivate var isValid: Bool = true

        fileprivate init(route: Route?, depth: Int) {
            self.route = route
            self.depth = depth
        }
    }

    private let container = UUID()
    private let rootSlot = UUID()
    private var acceptedSlots: [UUID] = []
    private let epoch = RUMSwiftUIViewTrackingEpoch()
    private var registration: RUMSwiftUIViewTrackingEpoch.Callback?
    private(set) var admission: RUMSwiftUIViewCallbackAdmission?
    private(set) var source: RUMSwiftUINavigationOccurrenceSource?
    private weak var observer: RUMSceneIdentifierReader.ObserverView?
    private var acceptedPath: [Route] = []
    private var hasAcceptedPath = false
    private var generation: UInt64 = 0
    private var needsInitialReconciliation = true
    private var metadata = RUMNavigationMetadata.automatic
    private var attachment: RUMViewTrackingState.Attachment = .detached
    private var detachGeneration: UInt64 = 0
    private var reconciliationEntry: UInt64 = 0

    #if DD_SDK_COMPILED_FOR_TESTING
    var acceptedDepth: Int { acceptedPath.count }
    #endif

    func configure(binding: RUMSwiftUIViewFoundationBinding?) -> RUMSwiftUIViewCallbackAdmission? {
        if let binding, let current = admission, current.isValid,
           current.binding.epoch == binding.epoch,
           current.binding.lifetime === binding.lifetime {
            return current
        }
        reconciliationEntry &+= 1
        let entry = reconciliationEntry
        let previousSource = source
        let previousAdmission = admission
        let previousRegistration = registration
        admission = nil
        registration = nil
        source = nil
        observer = nil
        attachment = .detached
        detachGeneration &+= 1
        needsInitialReconciliation = true
        if let previousAdmission {
            _ = previousSource?.cancelNavigationOwnedOccurrences(admission: previousAdmission)
        }
        guard reconciliationEntry == entry else {
            return nil
        }
        if let previousRegistration {
            epoch.retire(previousRegistration)
        }
        guard reconciliationEntry == entry else {
            return nil
        }
        guard let binding, let callback = epoch.enter(binding),
              let next = RUMSwiftUIViewCallbackAdmission(holder: epoch, callback: callback) else {
            return nil
        }
        registration = callback
        admission = next
        source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        return next
    }

    func reconcile(
        acceptedPath read: () -> [Route],
        metadata: RUMNavigationMetadata,
        admission expected: RUMSwiftUIViewCallbackAdmission?
    ) {
        reconciliationEntry &+= 1
        let entry = reconciliationEntry
        // Application binding effects remain independent of SDK admission.
        let path = read()
        guard accepts(entry: entry, admission: expected) else {
            return
        }
        reconcile(path: path, metadata: metadata, admission: expected)
    }

    func reconcile(
        path: [Route],
        metadata: RUMNavigationMetadata,
        admission expected: RUMSwiftUIViewCallbackAdmission?
    ) {
        if let expected {
            guard admits(expected) else {
                return
            }
        } else if admission != nil {
            return
        }
        reconciliationEntry &+= 1
        let entry = reconciliationEntry
        let previous = acceptedPath
        let previousSlots = acceptedSlots
        let previouslyAccepted = hasAcceptedPath
        let initiallyRequired = needsInitialReconciliation
        let offeredSource = source
        let priorGeneration = generation
        // Route equality and metadata belong to the application and may reenter.
        let changed = previouslyAccepted && previous != path
        var prefixCount = 0
        for (before, after) in zip(previous, path) {
            guard before == after else {
                break
            }
            prefixCount += 1
        }
        let slots = Array(previousSlots.prefix(prefixCount))
            + (prefixCount..<path.count).map { _ in UUID() }
        let nextGeneration = changed || (!previouslyAccepted && !path.isEmpty)
            ? priorGeneration &+ 1 : priorGeneration
        let change: RUMSwiftUINavigationOccurrenceSource.DestinationChange
        if initiallyRequired {
            change = .initial(requiresBootstrap: !path.isEmpty)
        } else if !changed {
            change = .unchanged
        } else if path.count < previous.count, Array(previous.prefix(path.count)) == path {
            change = .retainedReveal
        } else {
            change = .replacement
        }
        let configuration = configuration(
            route: path.last,
            depth: path.count,
            path: path,
            slots: slots,
            metadata: metadata,
            generation: nextGeneration
        )
        guard accepts(entry: entry, admission: expected), source === offeredSource else {
            return
        }
        acceptedPath = path
        acceptedSlots = slots
        hasAcceptedPath = true
        self.metadata = metadata
        generation = nextGeneration
        guard let expected, let offeredSource else {
            return
        }
        needsInitialReconciliation = false
        offeredSource.acceptDestination(
            occurrenceKey: configuration.occurrenceKey,
            bindingGeneration: configuration.bindingGeneration,
            change: change,
            admission: expected
        )
        guard accepts(entry: entry, admission: expected), source === offeredSource else {
            return
        }
        _ = offeredSource.reconcileCurrentDestination(configuration: configuration, admission: expected)
    }

    func makeClaim(for route: Route?) -> Claim {
        reconciliationEntry &+= 1
        let entry = reconciliationEntry
        let original = admission
        let path = acceptedPath
        let depth = depth(for: route, path: path)
        let claim = Claim(route: route, depth: depth)
        claim.isValid = accepts(entry: entry, admission: original)
        return claim
    }

    func configuration(
        for route: Route?,
        retaining claim: Claim,
        admission expected: RUMSwiftUIViewCallbackAdmission?
    ) -> RUMViewTrackingState.Configuration? {
        guard let expected, admits(expected) else {
            return nil
        }
        reconciliationEntry &+= 1
        let entry = reconciliationEntry
        let path = acceptedPath
        let slots = acceptedSlots
        let originalMetadata = metadata
        let originalGeneration = generation
        let originalSource = source
        let priorRoute = claim.route
        let priorDepth = claim.depth
        let currentDepth = depth(for: route, path: path)
        let selectedDepth = !claim.isValid || priorRoute != route || priorDepth > path.count ? currentDepth : priorDepth
        let configuration = configuration(
            route: route,
            depth: selectedDepth,
            path: path,
            slots: slots,
            metadata: originalMetadata,
            generation: originalGeneration
        )
        guard accepts(entry: entry, admission: expected), source === originalSource else {
            return nil
        }
        claim.route = route
        claim.depth = selectedDepth
        claim.isValid = true
        return configuration
    }

    func source(for expected: RUMSwiftUIViewCallbackAdmission) -> RUMSwiftUINavigationOccurrenceSource? {
        admits(expected) ? source : nil
    }

    func register(
        observer: RUMSceneIdentifierReader.ObserverView,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected) else {
            return
        }
        self.observer = observer
    }

    func reconcile(
        attachment: RUMViewTrackingState.Attachment,
        admission expected: RUMSwiftUIViewCallbackAdmission
    ) {
        guard admits(expected) else {
            return
        }
        detachGeneration &+= 1
        if case .attached(let scene?) = attachment {
            guard observer?.currentSceneIdentifier == scene, expected.admits(sceneIdentifier: scene) else {
                return
            }
            self.attachment = attachment
            if needsInitialReconciliation {
                reconcile(path: acceptedPath, metadata: metadata, admission: expected)
            }
            return
        }
        self.attachment = .detached
        let generation = detachGeneration
        // Root content disappears during a push; only the container reader owns teardown.
        DispatchQueue.main.async { [self, expected] in
            guard admits(expected), self.detachGeneration == generation, self.attachment == .detached else {
                return
            }
            _ = source?.cancelNavigationOwnedOccurrences(admission: expected)
            needsInitialReconciliation = true
        }
    }

    func sceneDidDisconnect(_ scene: UIScene, admission expected: RUMSwiftUIViewCallbackAdmission) {
        guard admits(expected) else {
            return
        }
        let identifier = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        if let current = observer?.window?.windowScene,
           current.session.persistentIdentifier == identifier.rawValue, current !== scene {
            return
        }
        guard attachment == .attached(identifier) else {
            return
        }
        observer?.markSceneDisconnected(identifier)
        source?.sceneDidDisconnect(identifier, admission: expected)
        attachment = .detached
        detachGeneration &+= 1
    }

    private func admits(_ expected: RUMSwiftUIViewCallbackAdmission) -> Bool {
        expected.isValid && admission?.matches(expected) == true
    }

    private func accepts(entry: UInt64, admission expected: RUMSwiftUIViewCallbackAdmission?) -> Bool {
        guard reconciliationEntry == entry else {
            return false
        }
        if let expected {
            return admits(expected)
        }
        return admission == nil
    }

    private func depth(for route: Route?, path: [Route]) -> Int {
        guard let route else {
            return 0
        }
        return path.lastIndex(of: route).map { $0 + 1 } ?? max(path.count, 1)
    }

    private func configuration(
        route: Route?,
        depth: Int,
        path: [Route],
        slots: [UUID],
        metadata: RUMNavigationMetadata,
        generation: UInt64
    ) -> RUMViewTrackingState.Configuration {
        let destination: RUMNavigationDestination
        if let route {
            destination = .route(route, occurrence: depth)
        } else {
            destination = .root(NativeRoot.root)
        }
        let view = metadata.view(for: destination)
        var attributes = view.attributes
        #if DD_SDK_COMPILED_FOR_TESTING
        let testSlot = depth > 0 && depth <= slots.count ? slots[depth - 1] : rootSlot
        attributes["native_test_claim"] = container.uuidString + ":" + String(depth) + ":" + testSlot.uuidString
        attributes["native_test_depth"] = depth
        #endif
        let slot = depth > 0 && depth <= slots.count ? slots[depth - 1] : rootSlot
        return .init(
            occurrenceKey: RUMViewOccurrenceKey(Position(container: container, slot: slot, depth: depth)),
            bindingGeneration: generation,
            descriptor: .init(name: view.name, path: view.path ?? view.name, attributes: attributes),
            isCurrentDestination: depth == path.count && route == path.last
        )
    }

    private enum NativeRoot: Hashable {
        case root
    }
}

@available(iOS 27.0, *)
@MainActor
private struct RUMNativeNavigationBoundary<Route: Hashable, Content: View>: View {
    let route: Route?
    let state: RUMNativeNavigationState<Route>
    let admission: RUMSwiftUIViewCallbackAdmission?
    let content: Content
    @State private var claim: RUMNativeNavigationState<Route>.Claim

    init(
        route: Route?,
        state: RUMNativeNavigationState<Route>,
        admission: RUMSwiftUIViewCallbackAdmission?,
        content: Content
    ) {
        self.route = route
        self.state = state
        self.admission = admission
        self.content = content
        _claim = State(initialValue: state.makeClaim(for: route))
    }

    var body: some View {
        let configuration = state.configuration(for: route, retaining: claim, admission: admission)
        let source = admission.flatMap { state.source(for: $0) }
        return content.background {
            if let admission, admission.isValid, let configuration, let source,
               state.source(for: admission) === source {
                rumMultiSceneTrackedContent(
                    Color.clear,
                    binding: admission.binding,
                    name: configuration.descriptor.name,
                    path: configuration.descriptor.path,
                    attributes: configuration.descriptor.attributes,
                    configuration: configuration,
                    navigationOccurrenceSource: source
                )
            }
        }
    }
}

#if DD_SDK_COMPILED_FOR_TESTING
/// Observes the real SDK boundary registration without owning its lifetime.
@available(iOS 27.0, *)
@MainActor
internal enum RUMNativeNavigationTesting {
    static var onBoundary: ((
        RUMSwiftUINavigationOccurrenceSource?, RUMSceneIdentifierReader.ObserverView,
        RUMViewTrackingState, RUMSwiftUIViewCallbackAdmission, RUMViewTrackingState.Configuration?
    ) -> Void)?
}
#endif

#endif
