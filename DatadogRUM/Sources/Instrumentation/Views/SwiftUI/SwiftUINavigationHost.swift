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

/// Tracks one admitted semantic container without changing its content identity.
@available(iOS 27.0, *)
@MainActor
internal struct RUMNavigationHost<Content: View>: View {
    private weak var core: DatadogCoreProtocol?
    private let transitions: RUMNavigationTransitions
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
        self.transitions = transitions
        self.content = content()
    }

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
            transitions: transitions
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
        if let source = selectedTransitions, let observationID {
            DispatchQueue.main.async {
                source.removeObserver(observationID)
            }
        }
    }

    func configure(
        transitions: RUMNavigationTransitions,
        binding: RUMSwiftUIViewFoundationBinding?
    ) -> RUMSwiftUIViewCallbackAdmission? {
        guard let binding else {
            if admission != nil {
                finish(stopOccurrence: true)
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
        if selectedTransitions == nil {
            configuredTransitions = transitions
        }
        return admission
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
        let id = observationID
        observationGeneration &+= 1
        attachmentGeneration &+= 1
        detachGeneration &+= 1
        requiresReaderMount = true
        attachment = .detached
        activeOccurrence = nil
        latestSnapshot = nil
        selectedTransitions = nil
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
    }
}

@available(iOS 27.0, *)
@MainActor
private struct RUMSemanticNavigationHostModifier: ViewModifier {
    let binding: RUMSwiftUIViewFoundationBinding?
    let transitions: RUMNavigationTransitions
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
            transitions: transitions,
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
#endif
