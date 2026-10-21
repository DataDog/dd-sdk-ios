/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import MachO
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
class SwiftUINavigationOwnershipTests: XCTestCase {
    // Each test owns a unique directory; simultaneous Core instances use separate directories below.
    private var temporaryCoreDirectory: CoreDirectory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryCoreDirectory = temporaryUniqueCoreDirectory()
        try temporaryCoreDirectory.create()
    }

    override func tearDownWithError() throws {
        defer {
            temporaryCoreDirectory = nil
        }
        if let directory = temporaryCoreDirectory {
            try directory.delete()
        }
        try super.tearDownWithError()
    }

    private func makeHandoffCore() -> DatadogCore {
        DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
    }

    @MainActor
    private func makeOwnedSwiftUIFeature(in core: DatadogCore) throws -> RUMFeature {
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core.flush()
        var configuration = RUM.Configuration(applicationID: "owned-swiftui", trackAnonymousUser: false)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        configuration.sessionSampleRate = 100
        configuration.vitalsUpdateFrequency = nil
        try RUM.enableOrThrow(with: configuration, in: core)
        core.flush()
        return try XCTUnwrap(core.get(feature: RUMFeature.self))
    }
}
#endif

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @MainActor
    func testSwiftUINavigationManagedRecord_whenOriginalSessionRetires_itPrunesWithoutBlockingValidPeer() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        // A/B are deliberately different Sessions of the SAME still-valid Foundation.
        for retireOriginal in [false, true] {
            let source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
            let firstHolder = RUMSwiftUIViewTrackingEpoch()
            let firstCallback = try XCTUnwrap(firstHolder.enter(binding))
            let first = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: firstHolder, callback: firstCallback))
            let secondHolder = RUMSwiftUIViewTrackingEpoch()
            let secondCallback = try XCTUnwrap(secondHolder.enter(binding))
            let second = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: secondHolder, callback: secondCallback))
            XCTAssertNotEqual(first.registrationIdentifier, second.registrationIdentifier)
            let configuration = configuration(generation: 1)
            source.acceptDestination(occurrenceKey: configuration.occurrenceKey, bindingGeneration: 1,
                                     change: .initial(requiresBootstrap: true), admission: first)
            XCTAssertTrue(source.reconcileCurrentDestination(configuration: configuration, admission: first).isEmpty)
            var initialCalls = 0
            let initial = try XCTUnwrap(first.withSession { session in
                source.resolveCandidate(candidateConfiguration: configuration, sceneIdentifier: scene,
                                        state: session.trackingState, admission: first) { value, scene in
                    initialCalls += 1
                    _ = first.withSession { current in
                        current.trackingState.reconcile(configuration: value, attachment: .attached(scene), isAppeared: true)
                    }
                }
            })
            XCTAssertEqual(initial, .handled)
            XCTAssertEqual(initialCalls, 1)
            XCTAssertEqual(first.withSession { $0.trackingState.activeLifecycleGeneration != nil }, true)
            if retireOriginal { firstHolder.retire(firstCallback) }
            XCTAssertTrue(binding.isValid)
            var peerCalls = 0
            let peer = try XCTUnwrap(second.withSession { session in
                source.resolveCandidate(candidateConfiguration: configuration, sceneIdentifier: scene,
                                        state: session.trackingState, admission: second) { value, scene in
                    peerCalls += 1
                    _ = second.withSession { current in
                        current.trackingState.reconcile(configuration: value, attachment: .attached(scene), isAppeared: true)
                    }
                }
            })
            XCTAssertEqual(peer, .handled)
            XCTAssertEqual(peerCalls, retireOriginal ? 1 : 0)
            XCTAssertEqual(second.withSession { $0.trackingState.activeLifecycleGeneration != nil }, true)
            XCTAssertEqual(first.isValid, !retireOriginal)
            if retireOriginal {
                // No expired Session/state escapes or getters are used by the test.
                XCTAssertNil(first.withSession { $0.trackingState.revision })
            } else {
                XCTAssertEqual(first.withSession { $0.trackingState.activeLifecycleGeneration == nil }, true)
            }
            secondHolder.retire(secondCallback)
            firstHolder.retire(firstCallback)
        }
    }

    @MainActor
    func testSwiftUINavigationPendingReveal_whenOriginalSessionRetires_itAllowsPeerMountInsteadOfRejectingIt() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        for retireOriginal in [false, true] {
            let source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
            let firstHolder = RUMSwiftUIViewTrackingEpoch()
            let firstCallback = try XCTUnwrap(firstHolder.enter(binding))
            let first = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: firstHolder, callback: firstCallback))
            let secondHolder = RUMSwiftUIViewTrackingEpoch()
            let secondCallback = try XCTUnwrap(secondHolder.enter(binding))
            let second = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: secondHolder, callback: secondCallback))
            let hidden = configuration(generation: 1)
            let revealed = configuration(generation: 2)
            var revealCalls = 0
            _ = first.withSession { session in
                _ = session.trackingState.reconcile(configuration: hidden, attachment: .attached(scene), isAppeared: true)
                _ = session.trackingState.disappear(configuration: hidden)
                session.navigationRegistration.rebind(to: source, state: session.trackingState,
                    configuration: hidden, attachment: .attached(scene), process: { value, scene in
                        revealCalls += 1
                        _ = first.withSession { current in
                            current.trackingState.reconcile(configuration: value, attachment: .attached(scene), isAppeared: true)
                        }
                    }, admission: first)
            }
            source.acceptDestination(occurrenceKey: revealed.occurrenceKey, bindingGeneration: 2,
                                     change: .unchanged, admission: first)
            XCTAssertTrue(source.reconcileCurrentDestination(configuration: revealed, admission: first).isEmpty)
            XCTAssertTrue(source.revealRetainedRoute(occurrenceKey: revealed.occurrenceKey,
                                                    bindingGeneration: 2, admission: first))
            XCTAssertEqual(revealCalls, 1)
            XCTAssertEqual(first.withSession { $0.trackingState.activeLifecycleGeneration != nil }, true)
            if retireOriginal { firstHolder.retire(firstCallback) }
            var peerCalls = 0
            let peer = try XCTUnwrap(second.withSession { session in
                source.resolveCandidate(candidateConfiguration: revealed, sceneIdentifier: scene,
                                        state: session.trackingState, admission: second) { _, _ in peerCalls += 1 }
            })
            XCTAssertEqual(peer, retireOriginal ? .allowOrdinaryMount : .handled)
            XCTAssertEqual(peerCalls, 0)
            if retireOriginal {
                let mount = try XCTUnwrap(second.withSession { session in
                    session.trackingState.reconcile(configuration: revealed, attachment: .attached(scene), isAppeared: true)
                })
                XCTAssertEqual(mount.count, 1)
                let firstTransition = try XCTUnwrap(mount.first)
                if case .start = firstTransition {} else { XCTFail("Fresh admitted peer must be allowed to start") }
                XCTAssertFalse(first.isValid)
            } else {
                XCTAssertTrue(first.isValid)
                XCTAssertEqual(first.withSession { $0.trackingState.activeLifecycleGeneration == nil }, true)
            }
            XCTAssertEqual(second.withSession { $0.trackingState.activeLifecycleGeneration != nil }, true)
            secondHolder.retire(secondCallback)
            firstHolder.retire(firstCallback)
        }
    }

    @MainActor
    func testSwiftUINavigationRebind_whenSourceIsForeignOrRetired_itPreservesOriginalEpochAndProcess() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let firstDirectory = try temporaryUniqueCoreDirectory().create()
        defer { try? firstDirectory.delete() }
        let secondDirectory = try temporaryUniqueCoreDirectory().create()
        defer { try? secondDirectory.delete() }
        let core = makeCore(in: firstDirectory)
        defer { core.stop() }
        let foreignCore = makeCore(in: secondDirectory)
        defer { foreignCore.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let foreignFeature = try makeOwnedSwiftUIFeature(in: foreignCore)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let foreignFoundation = try XCTUnwrap(foreignFeature.instrumentation.swiftUIViewFoundation)
        let foreignBinding = try XCTUnwrap(foreignFoundation.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        let foreign = RUMSwiftUINavigationOccurrenceSource(binding: foreignBinding)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        var originalCalls = 0
        var foreignCalls = 0
        for retireForeign in [false, true] {
            let base = configuration(generation: retireForeign ? 3 : 1)
            _ = admission.withSession { session in
                _ = session.trackingState.reconcile(configuration: base, attachment: .attached(scene), isAppeared: true)
                _ = session.trackingState.disappear(configuration: base)
                session.navigationRegistration.rebind(to: source, state: session.trackingState,
                    configuration: base, attachment: .attached(scene), process: { value, scene in
                        originalCalls += 1
                        XCTAssertEqual(value.descriptor.name, base.descriptor.name)
                        _ = admission.withSession { current in
                            current.trackingState.reconcile(configuration: value, attachment: .attached(scene), isAppeared: true)
                        }
                    }, admission: admission)
            }
            if retireForeign { foreignFoundation.retire() }
            let epoch = try XCTUnwrap(admission.withSession { $0.navigationRegistration.callbackEpoch })
            let replacement = configuration(generation: 99, name: "foreign")
            _ = admission.withSession { session in
                session.navigationRegistration.rebind(to: foreign, state: session.trackingState,
                    configuration: replacement, attachment: .detached,
                    process: { _, _ in foreignCalls += 1 }, admission: admission)
            }
            XCTAssertEqual(admission.withSession { $0.navigationRegistration.callbackEpoch }, epoch)
            XCTAssertTrue(admission.isValid)
            XCTAssertTrue(admission.fence.isActive)
            XCTAssertTrue(source.revealRetainedRoute(occurrenceKey: base.occurrenceKey,
                                                    bindingGeneration: base.bindingGeneration + 1, admission: admission))
            XCTAssertEqual(originalCalls, retireForeign ? 2 : 1)
            XCTAssertEqual(foreignCalls, 0)
        }
        holder.retire(callback)
    }

    @MainActor
    func testSwiftUINavigationRebind_withinSameSession_itReplacesOnlyLocalEpochAndKeepsOriginalFence() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let original = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        let replacement = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        let old = configuration(generation: 1)
        let current = configuration(generation: 2)
        var oldCalls = 0
        var newCalls = 0
        _ = admission.withSession { session in
            _ = session.trackingState.reconcile(configuration: current, attachment: .attached(scene), isAppeared: true)
            _ = session.trackingState.disappear(configuration: current)
            session.navigationRegistration.rebind(to: original, state: session.trackingState,
                configuration: current, attachment: .attached(scene),
                process: { _, _ in oldCalls += 1 }, admission: admission)
        }
        let oldEpoch = try XCTUnwrap(admission.withSession { $0.navigationRegistration.callbackEpoch })
        _ = admission.withSession { session in
            session.navigationRegistration.rebind(to: replacement, state: session.trackingState,
                configuration: current, attachment: .attached(scene), process: { value, scene in
                    newCalls += 1
                    _ = admission.withSession { current in
                        current.trackingState.reconcile(configuration: value, attachment: .attached(scene), isAppeared: true)
                    }
                }, admission: admission)
        }
        let newEpoch = try XCTUnwrap(admission.withSession { $0.navigationRegistration.callbackEpoch })
        XCTAssertGreaterThan(newEpoch, oldEpoch)
        XCTAssertTrue(admission.fence.isActive)
        _ = admission.withSession { session in
            session.navigationRegistration.rebind(to: original, state: session.trackingState,
                configuration: old, attachment: .detached, process: { _, _ in oldCalls += 1 }, admission: admission)
        }
        XCTAssertEqual(admission.withSession { $0.navigationRegistration.callbackEpoch }, newEpoch)
        XCTAssertFalse(original.revealRetainedRoute(occurrenceKey: current.occurrenceKey,
                                                  bindingGeneration: 3, admission: admission))
        XCTAssertTrue(replacement.revealRetainedRoute(occurrenceKey: current.occurrenceKey,
                                                    bindingGeneration: 3, admission: admission))
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
        holder.retire(callback)
        XCTAssertFalse(admission.fence.isActive)
        XCTAssertFalse(admission.isValid)
        XCTAssertNil(holder.withSession(for: callback) { $0.navigationRegistration.callbackEpoch })
    }

    @MainActor
    func testDeferredTransition_whenOriginalSessionRetires_itRefusesSuccessAndCancellationWithoutAdoptingReplacement() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        for cancelled in [false, true] {
            for retireOriginal in [false, true] {
                let holder = RUMSwiftUIViewTrackingEpoch()
                let callback = try XCTUnwrap(holder.enter(binding))
                let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
                let coordinator = RetainedCompletionCoordinator()
                let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
                    notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter,
                    admitsCallbacks: { binding.isValid }, coordinatorProvider: { _, _ in coordinator }
                )
                var deliveries = 0
                var deliveredTransitions = 0
                _ = admission.withSession { session in
                    arbiter.process(.keyedInitialMount(configuration: configuration(generation: 1), sceneIdentifier: scene),
                                    state: session.trackingState) { transitions in
                        deliveries += 1
                        deliveredTransitions += transitions.count
                    }
                }
                XCTAssertEqual(coordinator.registrations, 1)
                XCTAssertEqual(deliveries, 0)
                if retireOriginal { holder.retire(callback) }
                let replacement = retireOriginal ? try XCTUnwrap(holder.enter(binding)) : callback
                let before = try XCTUnwrap(holder.withSession(for: replacement) { $0.trackingState.revision })
                coordinator.complete(cancelled: cancelled)
                await drainOwnedMainDelivery()
                XCTAssertEqual(deliveries, (!cancelled && !retireOriginal) ? 1 : 0)
                XCTAssertEqual(deliveredTransitions, (!cancelled && !retireOriginal) ? 1 : 0)
                if cancelled || retireOriginal {
                    XCTAssertEqual(holder.withSession(for: replacement) { $0.trackingState.revision }, before)
                } else {
                    XCTAssertEqual(holder.withSession(for: callback) { $0.trackingState.activeLifecycleGeneration != nil }, true)
                }
                if retireOriginal { XCTAssertNil(admission.withSession { $0.trackingState.revision }) }
                holder.retire(replacement)
            }
        }
    }

    @MainActor
    func testRegistry_whenOriginalHolderRetiresOrReleases_itStopsSuppressingOnlyItsContainedSubtree() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let foundation = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation)
        let binding = try XCTUnwrap(foundation.makeBinding())
        let identifier = try connectedSceneIdentifier(binding)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.session.persistentIdentifier == identifier.rawValue })
        let delegate = try XCTUnwrap(windowScene.delegate as? UIWindowSceneDelegate)
        let window = try XCTUnwrap(delegate.window ?? nil, "Controls require the admitted test-host delegate's window")
        _ = try XCTUnwrap(window.windowScene === windowScene && windowScene.windows.contains { $0 === window }
                         && !window.isHidden && window.rootViewController != nil ? window : nil,
                         "Controls require the admitted test-host window and controller in the same scene")
        let hostRoot = try XCTUnwrap(window.rootViewController)
        for releaseHolder in [false, true] {
            var holder: RUMSwiftUIViewTrackingEpoch? = RUMSwiftUIViewTrackingEpoch()
            let callback = try XCTUnwrap(holder?.enter(binding))
            let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: try XCTUnwrap(holder), callback: callback))
            let contained = UIViewController()
            let sibling = UIViewController()
            for child in [contained, sibling] {
                hostRoot.addChild(child)
                hostRoot.view.addSubview(child.view)
                child.didMove(toParent: hostRoot)
            }
            defer {
                for child in [contained, sibling] {
                    child.willMove(toParent: nil)
                    child.view.removeFromSuperview()
                    child.removeFromParent()
                }
            }
            let observer = RUMSceneIdentifierReader.ObserverView(admission: admission, onChange: { _ in },
                                                                 applicationSupportsMultipleScenes: true)
            contained.view.addSubview(observer)
            let scene = try XCTUnwrap(observer.currentSceneIdentifier)
            XCTAssertEqual(scene, identifier)
            let coordinator = RetainedCompletionCoordinator()
            let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
                notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter,
                admitsCallbacks: { binding.isValid }, coordinatorProvider: { _, _ in coordinator }
            )
            let trackedConfiguration = configuration(generation: 1)
            _ = admission.withSession { session in
                _ = session.trackingState.reconcile(configuration: trackedConfiguration,
                                                    attachment: .attached(scene), isAppeared: true)
                foundation.registerAuthority(observer: observer, trackingState: session.trackingState, admission: admission)
                // Actual deferred production storage retains this appeared state after holder retirement.
                arbiter.process(.reconcile(configuration: trackedConfiguration, attachment: nil, isAppeared: false),
                                state: session.trackingState) { _ in XCTFail("Completion was not released") }
            }
            XCTAssertEqual(coordinator.registrations, 1)
            let eligible = try XCTUnwrap(foundation.makeEligibilityCheck())
            XCTAssertFalse(eligible(contained))
            XCTAssertTrue(eligible(sibling))
            if releaseHolder { holder = nil } else { holder?.retire(callback) }
            XCTAssertFalse(admission.fence.isActive)
            XCTAssertTrue(eligible(contained))
            XCTAssertTrue(eligible(sibling))
            arbiter.cancelPendingWithoutPublishing()
        }
    }

    @MainActor
    func testSceneReader_whenCreatedBeforeAttachment_itRegistersAuthorityOnMount() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Owned SwiftUI tracking requires iOS 27")
        }
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let foundation = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation)
        let binding = try XCTUnwrap(foundation.makeBinding())
        let eligible = try XCTUnwrap(foundation.makeEligibilityCheck())
        let container = UIViewController()
        let host = UIViewController()
        fixture.window.rootViewController = container
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        fixture.window.makeKeyAndVisible()
        XCTAssertTrue(host.view.window === fixture.window)
        let sibling = UIViewController()
        container.addChild(sibling)
        container.view.addSubview(sibling.view)
        sibling.didMove(toParent: container)
        defer {
            sibling.willMove(toParent: nil)
            sibling.view.removeFromSuperview()
            sibling.removeFromParent()
        }

        for hasMountCallback in [false, true] {
            let holder = RUMSwiftUIViewTrackingEpoch()
            let callback = try XCTUnwrap(holder.enter(binding))
            let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
            defer { holder.retire(callback) }
            let state = try XCTUnwrap(admission.withSession { $0.trackingState })
            _ = state.reconcile(
                configuration: configuration(generation: 1),
                attachment: .attached(fixture.identifier),
                isAppeared: true
            )
            var attachedRegistrations = 0
            var events: [String] = []
            let onMount: (@MainActor (RUMSceneIdentifier) -> Void)?
            if hasMountCallback {
                onMount = { _ in events.append("mount") }
            } else {
                onMount = nil
            }
            let reader = RUMSceneIdentifierReader(
                admission: admission,
                applicationSupportsMultipleScenes: true,
                onCreate: { observer in
                    if observer.window != nil {
                        attachedRegistrations += 1
                        events.append("register")
                    }
                    foundation.registerAuthority(observer: observer, trackingState: state, admission: admission)
                },
                onMount: onMount,
                onChange: { _ in }
            )
            let observer = RUMSceneIdentifierReader.ObserverView(
                admission: admission,
                onChange: { _ in },
                applicationSupportsMultipleScenes: true
            )
            defer { observer.removeFromSuperview() }
            reader.update(observer: observer)
            XCTAssertNil(observer.window)
            XCTAssertEqual(attachedRegistrations, 0)
            XCTAssertTrue(eligible(host))

            host.view.addSubview(observer)
            XCTAssertTrue(observer.window === fixture.window)
            XCTAssertEqual(observer.currentSceneIdentifier, fixture.identifier)
            XCTAssertTrue(observer.nearestViewController === host)
            XCTAssertEqual(attachedRegistrations, 1)
            XCTAssertEqual(events, hasMountCallback ? ["register", "mount"] : ["register"])
            XCTAssertFalse(eligible(host))
            XCTAssertTrue(eligible(sibling))

            observer.notifyCurrentAttachment()
            XCTAssertEqual(attachedRegistrations, 1)
            observer.removeFromSuperview()
            XCTAssertTrue(eligible(host))
            host.view.addSubview(observer)
            XCTAssertEqual(attachedRegistrations, 2)
            XCTAssertFalse(eligible(host))
            XCTAssertTrue(eligible(sibling))

            holder.retire(callback)
            observer.notifyCurrentAttachment()
            XCTAssertEqual(attachedRegistrations, 2)
            XCTAssertTrue(eligible(host))
            XCTAssertTrue(eligible(sibling))
        }
    }

    @MainActor
    func testSceneReader_whenMountRegistrationRetiresAdmission_itDoesNotPublishMount() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Owned SwiftUI tracking requires iOS 27")
        }
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        defer { holder.retire(callback) }
        let host = UIViewController()
        fixture.window.rootViewController = host
        fixture.window.makeKeyAndVisible()
        XCTAssertTrue(host.view.window === fixture.window)
        var attachedRegistrations = 0
        var mounts = 0
        let reader = RUMSceneIdentifierReader(
            admission: admission,
            applicationSupportsMultipleScenes: true,
            onCreate: { observer in
                if observer.window != nil {
                    attachedRegistrations += 1
                    holder.retire(callback)
                }
            },
            onMount: { _ in mounts += 1 },
            onChange: { _ in }
        )
        let observer = RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { _ in },
            applicationSupportsMultipleScenes: true
        )
        defer { observer.removeFromSuperview() }
        reader.update(observer: observer)
        host.view.addSubview(observer)
        XCTAssertEqual(attachedRegistrations, 1)
        XCTAssertFalse(admission.isValid)
        XCTAssertEqual(mounts, 0)
        observer.removeFromSuperview()
        host.view.addSubview(observer)
        XCTAssertEqual(attachedRegistrations, 1)
        XCTAssertEqual(mounts, 0)
    }

    @MainActor
    func testSceneReader_whenIdentifierIsNilForeignOrSessionExpired_itRefusesCallbacks() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        var changes = 0
        var mounts = 0
        let observer = RUMSceneIdentifierReader.ObserverView(admission: admission, onChange: { _ in changes += 1 },
                                                             onMount: { _ in mounts += 1 },
                                                             applicationSupportsMultipleScenes: true)
        observer.notify(attachment: .attached(nil))
        observer.notify(attachment: .attached(RUMSceneIdentifier(rawValue: UUID().uuidString)))
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(mounts, 0)
        observer.notify(attachment: .attached(scene))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(mounts, 1)
        holder.retire(callback)
        observer.notify(attachment: .detached)
        observer.markSceneDisconnected(scene)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(mounts, 1)
        XCTAssertEqual(observer.lastSceneIdentifier, scene)
    }

    @MainActor
    func testRetainedEligibilityAdmissionAndCompletion_whenCoreStops_itDoesNotRetainOriginalOwnershipGraph() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        var core: DatadogCore? = makeHandoffCore()
        defer { core?.stop() }
        weak var originalCore = core
        var feature: RUMFeature? = try makeOwnedSwiftUIFeature(in: try XCTUnwrap(core))
        weak var originalFeature = feature
        weak var originalMonitor = feature?.monitor
        weak var originalFoundation = feature?.instrumentation.swiftUIViewFoundation
        let binding = try XCTUnwrap(feature?.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let eligible = try XCTUnwrap(binding.foundation?.makeEligibilityCheck())
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        let coordinator = RetainedCompletionCoordinator()
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter,
            admitsCallbacks: { binding.isValid }, coordinatorProvider: { _, _ in coordinator }
        )
        var deliveries = 0
        _ = admission.withSession { session in
            arbiter.process(.keyedInitialMount(configuration: configuration(generation: 1), sceneIdentifier: scene),
                            state: session.trackingState) { _ in deliveries += 1 }
        }
        XCTAssertEqual(coordinator.registrations, 1)
        core?.flush()
        core?.stop()
        feature = nil
        core = nil
        await drainOwnedMainDelivery()
        XCTAssertNil(originalCore)
        XCTAssertNil(originalFeature)
        XCTAssertNil(originalMonitor)
        XCTAssertNil(originalFoundation)
        XCTAssertFalse(binding.isValid)
        XCTAssertFalse(eligible(UIViewController()))
        XCTAssertNil(admission.withSession { $0.trackingState.revision })
        coordinator.complete(cancelled: false)
        await drainOwnedMainDelivery()
        XCTAssertEqual(deliveries, 0)
        arbiter.cancelPendingWithoutPublishing()
    }

    @MainActor
    func testEligibilityCarrier_whenOriginalSubscriberChanges_itRefusesUntilOriginalMonitorReturns() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let foundation = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation)
        let handler = try XCTUnwrap(feature.instrumentation.viewsHandler as? RUMSceneViewsHandler)
        let eligible = try XCTUnwrap(foundation.makeEligibilityCheck())
        let candidate = UIViewController()
        XCTAssertTrue(eligible(candidate))
        handler.subscriber = nil
        XCTAssertFalse(eligible(candidate))
        let custom = RUMCommandSubscriberMock()
        handler.publish(to: custom)
        XCTAssertFalse(eligible(candidate))
        XCTAssertTrue(custom.receivedCommands.isEmpty)
        handler.publish(to: feature.monitor)
        XCTAssertTrue(eligible(candidate))
        foundation.retire()
        XCTAssertFalse(eligible(candidate))
    }

    @MainActor
    func testResolvedOffInstallation_keepsLegacyHandlerAndHasNoFoundationSlot() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("This control distinguishes the available resolved-Off branch") }
        let core = makeHandoffCore()
        defer { core.stop() }
        var config = RUM.Configuration(applicationID: "off-foundation-control", trackAnonymousUser: false)
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: false]
        config.sessionSampleRate = 100
        config.vitalsUpdateFrequency = nil
        try RUM.enableOrThrow(with: config, in: core)
        core.flush()
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertFalse(feature.isMultiSceneTrackingEnabled)
        XCTAssertTrue(feature.instrumentation.viewsHandler is RUMViewsHandler)
        XCTAssertFalse(feature.instrumentation.viewsHandler is RUMSceneViewsHandler)
        XCTAssertNil(feature.instrumentation.swiftUIViewFoundation)
        feature.instrumentation.installSwiftUIViewFoundation(feature: feature, core: core,
                                                            notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter)
        XCTAssertNil(feature.instrumentation.swiftUIViewFoundation)
    }

    @MainActor
    func testRetiredOnFoundation_staysInstalledAndCannotReplaceItsOccupiedSlot() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let original = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation)
        let handler = try XCTUnwrap(feature.instrumentation.viewsHandler as? RUMSceneViewsHandler)
        let lifetime = try XCTUnwrap(RUMSwiftUIViewLifetime(feature: feature, core: core))
        let candidate = try XCTUnwrap(RUMSwiftUIViewFoundation(instrumentation: feature.instrumentation,
                                                             handler: handler, lifetime: lifetime, epoch: UUID()))
        original.retire()
        XCTAssertTrue(feature.instrumentation.swiftUIViewFoundation === original)
        XCTAssertNil(original.makeBinding())
        XCTAssertFalse(handler.installSwiftUIViewFoundation(candidate,
            notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter))
        feature.instrumentation.installSwiftUIViewFoundation(feature: feature, core: core,
            notificationCenter: NotificationCenterProvider.makeTestProvider().applicationCenter)
        XCTAssertTrue(feature.instrumentation.swiftUIViewFoundation === original)
        XCTAssertNil(candidate.makeBinding())
    }

    @MainActor
    private func drainOwnedMainDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    func testFoundationActivation_whenOriginalSubscriberChangesDuringObserverRegistration_itKeepsFailedSlotClosed() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        for invalidateSubscriber in [false, true] {
            let directory = try temporaryUniqueCoreDirectory().create()
            defer { try? directory.delete() }
            let core = makeCore(in: directory)
            defer { core.stop() }
            let date = Date()
            core.contextProvider.write { context in
                context = .mockWith(
                    sdkInitDate: date,
                    launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                    applicationStateHistory: .mockWith(initialState: .active, date: date)
                )
            }
            core.flush()
            let custom = RUMCommandSubscriberMock()
            var registrations = 0
            weak var installedAtRegistration: RUMSwiftUIViewFoundation?
            let center = FoundationObserverRegistrationCenter { [weak core] in
                registrations += 1
                guard let core,
                      let feature = core.get(feature: RUMFeature.self),
                      let handler = feature.instrumentation.viewsHandler as? RUMSceneViewsHandler,
                      let foundation = feature.instrumentation.swiftUIViewFoundation else {
                    XCTFail("Observer registration requires the actual registered feature and occupied slot")
                    return
                }
                installedAtRegistration = foundation
                XCTAssertTrue(foundation.isValid)
                XCTAssertNotNil(foundation.makeBinding())
                if invalidateSubscriber { handler.publish(to: custom) }
            }
            var config = RUM.Configuration(applicationID: "foundation-activation-control", trackAnonymousUser: false)
            config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
            config.featureFlags = [.multiSceneTracking: true]
            config.sessionSampleRate = 100
            config.vitalsUpdateFrequency = nil
            config.notificationCenterProvider = NotificationCenterProvider(applicationCenter: center)
            try RUM.enableOrThrow(with: config, in: core)
            core.flush()
            let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
            let handler = try XCTUnwrap(feature.instrumentation.viewsHandler as? RUMSceneViewsHandler)
            let original = try XCTUnwrap(installedAtRegistration)
            XCTAssertEqual(registrations, 1)
            XCTAssertTrue(feature.instrumentation.swiftUIViewFoundation === original)
            let eligible = try XCTUnwrap(handler.swiftUIViewEligibility)
            let candidateView = UIViewController()
            if invalidateSubscriber {
                XCTAssertFalse(original.isValid)
                XCTAssertNil(original.makeBinding())
                XCTAssertNil(original.makeEligibilityCheck())
                XCTAssertFalse(eligible(candidateView))
                XCTAssertTrue(custom.receivedCommands.isEmpty)
                handler.publish(to: feature.monitor)
                XCTAssertFalse(original.isValid)
                XCTAssertNil(original.makeBinding())
                XCTAssertFalse(handler.swiftUIViewEligibility?(candidateView) == true)
                let lifetime = try XCTUnwrap(RUMSwiftUIViewLifetime(feature: feature, core: core))
                let replacement = try XCTUnwrap(RUMSwiftUIViewFoundation(
                    instrumentation: feature.instrumentation, handler: handler,
                    lifetime: lifetime, epoch: UUID()
                ))
                XCTAssertFalse(handler.installSwiftUIViewFoundation(replacement, notificationCenter: center))
                feature.instrumentation.installSwiftUIViewFoundation(feature: feature, core: core,
                                                                     notificationCenter: center)
                XCTAssertTrue(feature.instrumentation.swiftUIViewFoundation === original)
                XCTAssertNil(replacement.makeBinding())
                XCTAssertFalse(handler.swiftUIViewEligibility?(candidateView) == true)
            } else {
                XCTAssertTrue(original.isValid)
                XCTAssertNotNil(original.makeBinding())
                XCTAssertNotNil(original.makeEligibilityCheck())
                XCTAssertTrue(eligible(candidateView))
            }
        }
    }

    @MainActor
    private func connectedSceneIdentifier(_ binding: RUMSwiftUIViewFoundationBinding) throws -> RUMSceneIdentifier {
        // Production scene proof is never replaced by a fabricated identifier.
        // A missing admitted host scene is not qualification of these controls.
        let expectedDelegateClass = try XCTUnwrap(NSClassFromString("Example.MountedWebViewSceneDelegate"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
            $0.activationState != .unattached && $0.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expectedDelegateClass)
            } == true
        }, "Controls require the actual connected UIKit test-host scene and delegate")
        let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
        let window = try XCTUnwrap(delegate.window ?? nil, "Controls require the test-host delegate's window")
        _ = try XCTUnwrap(window.windowScene === scene && scene.windows.contains { $0 === window }
                         && !window.isHidden && window.rootViewController != nil ? window : nil,
                         "Controls require a visible test-host window and root controller in the same scene")
        let identifier = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        guard admission.admits(sceneIdentifier: identifier) else {
            holder.retire(callback)
            throw XCTSkip("No scene admitted by the actual Foundation; control remains unqualified")
        }
        holder.retire(callback)
        return identifier
    }

    private func configuration(generation: UInt64, name: String = "route") -> RUMViewTrackingState.Configuration {
        .init(occurrenceKey: RUMViewOccurrenceKey("route"), bindingGeneration: generation,
              descriptor: .init(name: name, path: name, attributes: [:]))
    }

    private func makeCore(in directory: CoreDirectory) -> DatadogCore {
        DatadogCore(directory: directory, dateProvider: SystemDateProvider(), initialConsent: .notGranted,
                    performance: .mockAny(), httpClient: HTTPClientMock(), encryption: nil,
                    contextProvider: .mockAny(), applicationVersion: .mockAny(), maxBatchesPerUpload: 1,
                    backgroundTasksEnabled: false)
    }
}

@MainActor
private final class RetainedCompletionCoordinator: RUMSwiftUITransitionCoordinating {
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var initiallyInteractive: Bool { true }
    private(set) var registrations = 0
    private var completion: ((Bool) -> Void)?

    func registerCompletion(_ completion: @escaping (Bool) -> Void) -> Bool {
        registrations += 1
        self.completion = completion
        return true
    }

    func complete(cancelled: Bool) {
        let callback = completion
        completion = nil
        callback?(cancelled)
    }
}

@available(iOS 27.0, *)
private final class FoundationObserverRegistrationCenter: NotificationCenter, @unchecked Sendable {
    private let onDisconnectObserverRegistration: @MainActor () -> Void

    init(onDisconnectObserverRegistration: @escaping @MainActor () -> Void) {
        self.onDisconnectObserverRegistration = onDisconnectObserverRegistration
        super.init()
    }

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
                              using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
        if name == UIScene.didDisconnectNotification {
            guard Thread.isMainThread else {
                XCTFail("Foundation registration must remain on the owning main actor")
                return token
            }
            MainActor.assumeIsolated { onDisconnectObserverRegistration() }
        }
        return token
    }
}

#endif

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @MainActor
    func testDisappearanceCallback_keepsItsRegistrationUntilReleaseAndStopsOnlyOnce() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        var holder: RUMSwiftUIViewTrackingEpoch? = RUMSwiftUIViewTrackingEpoch()
        weak var originalHolder = holder
        let callback = try XCTUnwrap(holder?.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: try XCTUnwrap(holder), callback: callback))
        weak var originalSession = try XCTUnwrap(admission.withSession { $0 })
        _ = admission.withSession { session in
            _ = session.trackingState.update(attachment: .attached(scene))
            _ = session.trackingState.appear()
        }
        let identity = try XCTUnwrap(admission.withSession { $0.trackingState.identity })
        var transitions: [RUMViewTrackingState.Transition] = []
        var disappearance: (() -> Void)? = admission.disappearanceCallback {
            _ = admission.withSession { transitions += $0.trackingState.disappear() }
        }
        holder = nil
        XCTAssertNotNil(originalHolder)
        XCTAssertNotNil(originalSession)
        XCTAssertTrue(admission.isValid)
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(transitions, [.stop(identity: identity, sceneIdentifier: scene)])
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(transitions, [.stop(identity: identity, sceneIdentifier: scene)])
        disappearance = nil
        XCTAssertNil(originalHolder)
        XCTAssertNil(originalSession)
        XCTAssertFalse(admission.isValid)
        XCTAssertFalse(admission.fence.isActive)
    }

    @MainActor
    func testDisappearanceCallback_whenItsRegistrationRetires_itCannotMutateTheReplacement() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let core = makeHandoffCore()
        defer { core.stop() }
        let feature = try makeOwnedSwiftUIFeature(in: core)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let scene = try connectedSceneIdentifier(binding)
        let holder = RUMSwiftUIViewTrackingEpoch()
        let callback = try XCTUnwrap(holder.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: callback))
        var admittedCalls = 0
        let disappearance = admission.disappearanceCallback {
            _ = admission.withSession {
                admittedCalls += 1
                _ = $0.trackingState.disappear()
            }
        }
        holder.retire(callback)
        let replacement = try XCTUnwrap(holder.enter(binding))
        let current = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: holder, callback: replacement))
        _ = current.withSession { session in
            _ = session.trackingState.update(attachment: .attached(scene))
            _ = session.trackingState.appear()
        }
        let revision = try XCTUnwrap(current.withSession { $0.trackingState.revision })
        disappearance()
        XCTAssertEqual(admittedCalls, 0)
        XCTAssertFalse(admission.isValid)
        XCTAssertEqual(current.withSession { $0.trackingState.revision }, revision)
        XCTAssertEqual(current.withSession { $0.trackingState.isAppeared }, true)
        holder.retire(replacement)
    }

    @MainActor
    func testDisappearanceCallback_whenCoreStops_itDoesNotRetainTheOwnershipGraph() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        var core: DatadogCore? = makeHandoffCore()
        defer { core?.stop() }
        weak var originalCore = core
        var feature: RUMFeature? = try makeOwnedSwiftUIFeature(in: try XCTUnwrap(core))
        weak var originalFeature = feature
        weak var originalMonitor = feature?.monitor
        weak var originalFoundation = feature?.instrumentation.swiftUIViewFoundation
        let binding = try XCTUnwrap(feature?.instrumentation.swiftUIViewFoundation?.makeBinding())
        var holder: RUMSwiftUIViewTrackingEpoch? = RUMSwiftUIViewTrackingEpoch()
        weak var originalHolder = holder
        let callback = try XCTUnwrap(holder?.enter(binding))
        let admission = try XCTUnwrap(RUMSwiftUIViewCallbackAdmission(holder: try XCTUnwrap(holder), callback: callback))
        weak var originalSession = try XCTUnwrap(admission.withSession { $0 })
        let observer = RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { _ in },
            applicationSupportsMultipleScenes: true
        )
        let source = RUMSwiftUINavigationOccurrenceSource(binding: binding)
        var admittedCalls = 0
        var disappearance: (() -> Void)? = admission.disappearanceCallback {
            _ = admission.withSession { _ in admittedCalls += 1 }
        }
        holder = nil
        core?.flush()
        core?.stop()
        feature = nil
        core = nil
        await drainOwnedMainDelivery()
        XCTAssertNotNil(originalHolder)
        XCTAssertNil(originalCore)
        XCTAssertNil(originalFeature)
        XCTAssertNil(originalMonitor)
        XCTAssertNil(originalFoundation)
        XCTAssertFalse(binding.isValid)
        try XCTUnwrap(disappearance)()
        XCTAssertEqual(admittedCalls, 0)
        disappearance = nil
        withExtendedLifetime((observer, source, admission)) {
            XCTAssertNil(originalHolder)
            XCTAssertNil(originalSession)
        }
    }

    @MainActor
    func testOrdinaryTrackedView_preservesItsOccurrenceAndRoutesEventsToItsHostScene() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Owned SwiftUI tracking requires iOS 27") }
        let expectedDelegate = try XCTUnwrap(NSClassFromString(
            "Example.MountedWebViewSceneDelegate"
        ))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState != .unattached && $0.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expectedDelegate)
            } == true
        }
        XCTAssertEqual(scenes.count, 1)
        let scene = try XCTUnwrap(scenes.first)
        let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
        let window = try XCTUnwrap(delegate.window ?? nil)
        let originalRoot = try XCTUnwrap(window.rootViewController)
        let originalHidden = window.isHidden
        let originalKey = scene.windows.first(where: \.isKeyWindow)
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let rows = OrdinarySwiftUIViewRows()
        let core = DatadogCore(
            directory: temporaryCoreDirectory, dateProvider: SystemDateProvider(), initialConsent: .granted,
            performance: .mockAny(), httpClient: HTTPClientMock(), encryption: nil,
            contextProvider: .mockAny(), applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1, backgroundTasksEnabled: false
        )
        defer { core.stop() }
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core.flush()
        var config = RUM.Configuration(applicationID: "ordinary-owned-swiftui", trackAnonymousUser: false)
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        config.sessionSampleRate = 100
        config.vitalsUpdateFrequency = nil
        config.viewEventMapper = { rows.append($0); return $0 }
        try RUM.enableOrThrow(with: config, in: core)
        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNotNil(feature.instrumentation.swiftUIViewFoundation)
        guard RUMSwiftUIViewCallbackAdmission.lifecycleObserver == nil else {
            XCTFail("An unrelated SwiftUI lifecycle observer is already installed")
            return
        }
        var observationBoundary = "mount"
        var lifecycleObservations: [OrdinarySwiftUILifecycleObservation] = []
        var droppedLifecycleObservations = 0
        var mountedRegistrationIdentifier: UUID?
        var mountedFoundationEpoch: UUID?
        var mountedTrackingIdentity: String?
        RUMSwiftUIViewCallbackAdmission.lifecycleObserver = { observation in
            if lifecycleObservations.count < 256 {
                lifecycleObservations.append(.init(
                    sequence: lifecycleObservations.count,
                    boundary: observationBoundary,
                    observation: observation
                ))
            } else {
                droppedLifecycleObservations += 1
            }
        }
        var boundaries: [[String: Any]] = []
        var firstDriver: OrdinarySwiftUIViewDriver? = OrdinarySwiftUIViewDriver()
        var secondDriver: OrdinarySwiftUIViewDriver?
        defer {
            RUMSwiftUIViewCallbackAdmission.lifecycleObserver = nil
            firstDriver?.update = nil
            secondDriver?.update = nil
            window.rootViewController = originalRoot
            window.isHidden = originalHidden
            originalKey?.makeKey()
        }
        let driver = try XCTUnwrap(firstDriver)
        let child = OrdinarySwiftUIViewChild(driver: driver)
        let expectedPath = "OnTracked/\(child.typeDescription.hashValue)"
        let tracked = AnyView(child.trackRUMView(name: "OnTracked", attributes: ["probe": "on", "sample": 7], in: core))
        let host = UIHostingController(rootView: OrdinarySwiftUIViewRoot(content: tracked, driver: driver))
        window.rootViewController = host
        window.makeKeyAndVisible()
        func snapshot() -> RUMCoreContext? { feature.monitor.rumContextSnapshot(for: .scene(sceneID)) }
        func selectedViews(_ ids: Set<String>) -> [RUMViewEvent] {
            rows.views.filter { ids.contains($0.view.id) || $0.view.name == "OnTracked" }
        }
        func record(_ phase: String, _ expectedHost: UIViewController) {
            XCTAssertTrue(window.windowScene === scene)
            XCTAssertTrue(scene.windows.contains { $0 === window })
            XCTAssertTrue(window.rootViewController === expectedHost)
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertFalse(window.isHidden)
            XCTAssertTrue(window.bounds.width.isFinite && window.bounds.height.isFinite
                          && window.bounds.width > 0 && window.bounds.height > 0)
            let context = snapshot()
            boundaries.append([
                "phase": phase, "scene_identifier": scene.session.persistentIdentifier,
                "window_identity": String(describing: ObjectIdentifier(window)),
                "root_identity": String(describing: ObjectIdentifier(expectedHost)),
                "is_key": window.isKeyWindow, "visible": !window.isHidden,
                "scene_matches": window.windowScene === scene,
                "root_matches": window.rootViewController === expectedHost,
                "width": Double(window.bounds.width), "height": Double(window.bounds.height),
                "context": context.map {
                    ["session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                     "name": $0.viewName ?? "", "path": $0.viewPath ?? ""]
                } ?? [:]
            ])
        }
        var attemptedBoundary = "mount"
        var observedViewIDs: [String] = []
        var terminalCaptured = false
        defer {
            if !terminalCaptured {
                do {
                    let context = snapshot()
                    let raw = rows.views
                    let encoded = try raw.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    }
                    let partial: [String: Any] = [
                        "schema_version": 1, "family": "swiftui-on-public-entry-partial",
                        "terminal": false, "attempted_boundary": attemptedBoundary,
                        "pid": Int(ProcessInfo.processInfo.processIdentifier),
                        "scene_identifier": scene.session.persistentIdentifier,
                        "stable_states": driver.states,
                        "reconstructed_states": secondDriver?.states ?? [],
                        "first_disappearances": driver.disappearances,
                        "second_disappearances": secondDriver?.disappearances ?? 0,
                        "scene_view_absent": context?.viewID == nil,
                        "first_view_inactive": observedViewIDs.first.map { id in
                            raw.contains { $0.view.id == id && $0.view.isActive == false }
                        } ?? false,
                        "observed_view_ids": observedViewIDs,
                        "context": context.map {
                            ["session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                             "name": $0.viewName ?? "", "path": $0.viewPath ?? ""]
                        } ?? [:],
                        "boundaries": boundaries, "view_rows": encoded,
                        "lifecycle_observations": try JSONSerialization.jsonObject(
                            with: JSONEncoder().encode(lifecycleObservations)
                        ),
                        "dropped_lifecycle_observations": droppedLifecycleObservations,
                        "lifecycle_observer_installed": RUMSwiftUIViewCallbackAdmission.lifecycleObserver != nil,
                        "mounted_registration_identifier": mountedRegistrationIdentifier?.uuidString ?? "",
                        "mounted_foundation_epoch": mountedFoundationEpoch?.uuidString ?? "",
                        "mounted_tracking_identity": mountedTrackingIdentity ?? "",
                        "window_is_key": window.isKeyWindow,
                        "window_visible": !window.isHidden,
                        "window_scene_matches": window.windowScene === scene,
                        "root_is_original_host": window.rootViewController === host,
                        "window_width": Double(window.bounds.width),
                        "window_height": Double(window.bounds.height)
                    ]
                    let capture = XCTAttachment(
                        data: try JSONSerialization.data(withJSONObject: partial),
                        uniformTypeIdentifier: "public.json"
                    )
                    capture.name = "ordinary-swiftui-public-entry-partial"
                    capture.lifetime = .keepAlways
                    add(capture)
                } catch {
                    XCTFail("Could not retain ordinary SwiftUI partial observations")
                }
            }
        }
        try await awaitOrdinaryBoundary("mount", core: core) {
            driver.states == [0] && snapshot()?.viewName == "OnTracked"
                && rows.views.contains { $0.view.isActive == true }
        }
        let first = try XCTUnwrap(snapshot())
        let firstID = try XCTUnwrap(first.viewID)
        observedViewIDs.append(firstID)
        let mountedObservation = lifecycleObservations.first {
            $0.boundary == "mount" && $0.observation.phase == "trait-publisher-call"
                && $0.observation.transitions.contains { $0.kind == "start" }
        }?.observation
        mountedRegistrationIdentifier = mountedObservation?.registrationIdentifier
        mountedFoundationEpoch = mountedObservation?.foundationEpoch
        mountedTrackingIdentity = mountedObservation?.trackingIdentity
        XCTAssertEqual(first.viewPath, expectedPath)
        XCTAssertEqual(Set(selectedViews([firstID]).map { $0.view.id }), [firstID])
        record("mount", host)
        observationBoundary = "child-state-update"
        try XCTUnwrap(driver.update)()
        attemptedBoundary = "child-state-update"
        try await awaitOrdinaryBoundary("child-state-update", core: core) { driver.states == [0, 1] }
        let retained = try XCTUnwrap(snapshot())
        XCTAssertEqual(retained.sessionID, first.sessionID)
        XCTAssertEqual(retained.viewID, firstID)
        XCTAssertEqual(retained.viewName, first.viewName)
        XCTAssertEqual(retained.viewPath, expectedPath)
        XCTAssertEqual(Set(selectedViews([firstID]).map { $0.view.id }), [firstID])
        record("child-state-update", host)
        observationBoundary = "unmount"
        driver.visible = false
        attemptedBoundary = "unmount"
        try await awaitOrdinaryBoundary("unmount", core: core) {
            driver.disappearances == 1 && snapshot()?.viewID == nil
                && rows.views.contains { $0.view.id == firstID && $0.view.isActive == false }
        }
        XCTAssertNil(snapshot())
        record("unmount", host)
        driver.update = nil
        firstDriver = nil
        let next = OrdinarySwiftUIViewDriver()
        secondDriver = next
        let rebuilt = AnyView(OrdinarySwiftUIViewChild(driver: next).trackRUMView(
            name: "OnTracked", attributes: ["probe": "on", "sample": 7], in: core
        ))
        let nextHost = UIHostingController(rootView: OrdinarySwiftUIViewRoot(content: rebuilt, driver: next))
        observationBoundary = "reconstruction"
        window.rootViewController = nextHost
        attemptedBoundary = "reconstruction"
        try await awaitOrdinaryBoundary("reconstruction", core: core) {
            next.states == [0] && snapshot()?.viewName == "OnTracked" && snapshot()?.viewID != firstID
        }
        let second = try XCTUnwrap(snapshot())
        let secondID = try XCTUnwrap(second.viewID)
        observedViewIDs.append(secondID)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertEqual(second.viewPath, expectedPath)
        record("reconstruction", nextHost)
        observationBoundary = "reconstructed-unmount"
        next.visible = false
        attemptedBoundary = "reconstructed-unmount"
        try await awaitOrdinaryBoundary("reconstructed-unmount", core: core) {
            next.disappearances == 1 && snapshot()?.viewID == nil
                && rows.views.contains { $0.view.id == secondID && $0.view.isActive == false }
        }
        XCTAssertNil(snapshot())
        record("reconstructed-unmount", nextHost)
        next.update = nil
        let raw = rows.views
        let expectedViewIDs: Set<String> = [firstID, secondID]
        let selectedIndices = raw.indices.filter {
            expectedViewIDs.contains(raw[$0].view.id) || raw[$0].view.name == "OnTracked"
        }
        let actual = selectedIndices.map { raw[$0] }
        XCTAssertEqual(Set(actual.map { $0.view.id }), [firstID, secondID])
        for value in actual {
            XCTAssertEqual(value.session.id, first.sessionID)
        }
        let selectedEncoded: [[String: Any]] = try actual.map {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
            let row = try XCTUnwrap(object as? [String: Any])
            let context = try XCTUnwrap(row["context"] as? [String: Any])
            XCTAssertEqual(context["probe"] as? String, "on")
            XCTAssertEqual(context["sample"] as? Int, 7)
            XCTAssertEqual($0.view.name, "OnTracked")
            XCTAssertEqual($0.view.url, expectedPath)
            return row
        }
        let encoded: [[String: Any]] = try raw.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any])
        }
        let payload: [String: Any] = [
            "schema_version": 1, "family": "swiftui-on-public-entry", "terminal": true,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "loaded_images": (0..<_dyld_image_count()).compactMap { _dyld_get_image_name($0).map(String.init(cString:)) },
            "scene_identifier": scene.session.persistentIdentifier,
            "expected_path": expectedPath, "stable_states": driver.states,
            "reconstructed_states": next.states, "boundaries": boundaries, "view_rows": encoded,
            "lifecycle_observations": try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(lifecycleObservations)
            ),
            "dropped_lifecycle_observations": droppedLifecycleObservations,
            "lifecycle_observer_installed": RUMSwiftUIViewCallbackAdmission.lifecycleObserver != nil,
            "mounted_registration_identifier": mountedRegistrationIdentifier?.uuidString ?? "",
            "mounted_foundation_epoch": mountedFoundationEpoch?.uuidString ?? "",
            "mounted_tracking_identity": mountedTrackingIdentity ?? "",
            "selected_view_row_indices": selectedIndices, "selected_view_rows": selectedEncoded,
            "mounted_session_id": first.sessionID, "expected_view_ids": [firstID, secondID]
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: payload), uniformTypeIdentifier: "public.json")
        attachment.name = "ordinary-swiftui-public-entry-terminal"
        attachment.lifetime = .keepAlways
        add(attachment)
        terminalCaptured = true
    }

    @MainActor
    private func awaitOrdinaryBoundary(
        _ name: String, core: DatadogCore, condition: () -> Bool
    ) async throws {
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            core.flush()
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing ordinary SwiftUI boundary: \(name)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(name)
    }
}

private enum OrdinarySwiftUIViewCaptureError: Error { case missingBoundary(String) }

private struct OrdinarySwiftUILifecycleObservation: Encodable {
    let sequence: Int
    let boundary: String
    let observation: RUMSwiftUIViewCallbackAdmission.LifecycleObservation
}

private final class OrdinarySwiftUIViewRows: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RUMViewEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var views: [RUMViewEvent] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

@MainActor
private final class OrdinarySwiftUIViewDriver: ObservableObject {
    @Published var visible = true
    var states: [Int] = []
    var disappearances = 0
    var update: (() -> Void)?
}

private struct OrdinarySwiftUIViewChild: View {
    let driver: OrdinarySwiftUIViewDriver
    @State private var counter = 0
    var body: some View {
        Text("Counter \(counter)")
            .onAppear { driver.states.append(counter); driver.update = { counter += 1 } }
            .onChange(of: counter) { driver.states.append($0) }
            .onDisappear { driver.disappearances += 1 }
    }
}

private struct OrdinarySwiftUIViewRoot: View {
    let content: AnyView
    @ObservedObject var driver: OrdinarySwiftUIViewDriver
    var body: some View { if driver.visible { content } }
}
#endif

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    private enum NavigationSourceRoute: Hashable {
        case home
        case detail(secret: String)
    }

    @MainActor
    func testNavigationTransitions_whenProposalIsCancelled_itPreservesCommittedOccurrence() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic navigation requires iOS 27") }
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observer = source.observe { snapshots.append($0) }
        defer { source.removeObserver(observer) }

        source.willNavigate(id: "cancelled", destination: RUMView(name: "Detail"))
        source.cancel(id: "cancelled")
        source.commit(id: "cancelled")
        XCTAssertEqual(snapshots.map(\.generation), [0])
        XCTAssertEqual(snapshots.map { $0.destination.name }, ["Home"])

        source.willNavigate(id: "accepted", destination: RUMView(name: "Detail"))
        source.commit(id: "accepted")
        source.commit(id: "accepted")
        XCTAssertEqual(snapshots.map(\.generation), [0, 1])
        XCTAssertEqual(snapshots.map { $0.destination.name }, ["Home", "Detail"])
    }

    @MainActor
    func testNavigationTransitions_whenObserverCommitsReentrantly_itDoesNotResumeObsoleteDelivery() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic navigation requires iOS 27") }
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var generations = [[UInt64](), [UInt64]()]
        var nestedCommit = false
        let observers = (0..<2).map { index in
            source.observe { snapshot in
                generations[index].append(snapshot.generation)
                if snapshot.generation == 1, !nestedCommit {
                    nestedCommit = true
                    source.willNavigate(id: "nested", destination: RUMView(name: "Returned Home"))
                    source.commit(id: "nested")
                }
            }
        }
        defer { observers.forEach(source.removeObserver) }

        source.willNavigate(id: "outer", destination: RUMView(name: "Detail"))
        source.commit(id: "outer")
        XCTAssertTrue(nestedCommit)
        for delivered in generations {
            XCTAssertEqual(delivered.first, 0)
            XCTAssertEqual(delivered.last, 2)
            XCTAssertTrue(zip(delivered, delivered.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        }
    }

    @MainActor
    func testObservedNavigation_whenEqualRoutesHaveDistinctOccurrences_itPublishesBeforeSendReturns() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic navigation requires iOS 27") }
        let secret = "associated-value-must-stay-local"
        let updates = CurrentValueSubject<RUMNavigationDestination, Never>(.root(NavigationSourceRoute.home))
        let observed = RUMNavigationObservedTransitions(
            updates: updates, acceptsDelivery: { true }, destination: { $0 }
        )
        defer { observed.stop() }
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observer = observed.transitions.observe { snapshots.append($0) }
        defer { observed.transitions.removeObserver(observer) }
        XCTAssertEqual(snapshots.map(\.generation), [0])

        updates.send(.route(NavigationSourceRoute.detail(secret: secret), occurrence: 1))
        XCTAssertEqual(snapshots.map(\.generation), [0, 1])
        updates.send(.route(NavigationSourceRoute.detail(secret: secret), occurrence: 1))
        XCTAssertEqual(snapshots.map(\.generation), [0, 1])
        updates.send(.route(NavigationSourceRoute.detail(secret: secret), occurrence: 2))
        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2])
        XCTAssertEqual(snapshots.map { $0.destination.name }, ["Home", "Detail", "Detail"])
        XCTAssertEqual(snapshots[1].destination.name, snapshots[2].destination.name)
        for snapshot in snapshots {
            XCTAssertFalse(snapshot.destination.name.contains(secret))
            XCTAssertFalse((snapshot.destination.path ?? "").contains(secret))
        }
    }

    private struct NavigationSourceReentrantValue: Hashable {
        let value: Int
        let onEquality: () -> Void
        let onHash: () -> Void

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.onEquality()
            return lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            onHash()
            hasher.combine(value)
        }
    }

    @MainActor
    func testObservedNavigation_whenApplicationCallbacksReenter_itKeepsNewestDelivery() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic navigation requires iOS 27") }
        enum Boundary: CaseIterable { case admission, projection, identity, metadata }

        for boundary in Boundary.allCases {
            let updates = PassthroughSubject<Int, Never>()
            var currentInput = 0
            var reentered = false
            let trigger: (Boundary, Int) -> Void = { candidate, value in
                if candidate == boundary, value == 1, !reentered {
                    reentered = true
                    updates.send(2)
                }
            }
            func value(_ number: Int) -> NavigationSourceReentrantValue {
                NavigationSourceReentrantValue(
                    value: number,
                    onEquality: { trigger(.identity, number) },
                    onHash: { trigger(.metadata, number) }
                )
            }
            let metadata = RUMNavigationMetadata.automatic.overriding(value(99), name: "Unused")
            let observed = RUMNavigationObservedTransitions(
                updates: updates.handleEvents(receiveOutput: { currentInput = $0 }),
                acceptsDelivery: {
                    let input = currentInput
                    trigger(.admission, input)
                    return !(boundary == .admission && input == 1)
                },
                destination: { input in
                    trigger(.projection, input)
                    return .route(value(input), attributes: ["source": input])
                },
                metadata: metadata
            )
            var delivered: [Int] = []
            let observer = observed.transitions.observe { snapshot in
                delivered.append(snapshot.destination.attributes["source"] as? Int ?? -1)
            }
            updates.send(0)
            updates.send(1)
            XCTAssertTrue(reentered, "Missing actual callback at \(boundary)")
            XCTAssertEqual(delivered, [0, 2], "Obsolete outer callback at \(boundary)")
            updates.send(3)
            XCTAssertEqual(delivered, [0, 2, 3], "Newer admission was stopped at \(boundary)")
            observed.transitions.removeObserver(observer)
            observed.stop()
        }
    }

    @MainActor
    func testObservedNavigation_whenAdmissionExpiresBeforeQueuedDelivery_itDoesNotProjectOrCommit() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic navigation requires iOS 27") }
        let updates = PassthroughSubject<Int, Never>()
        var admitted = true
        var projections = 0
        let receivedBySubscription = DispatchSemaphore(value: 0)
        let observed = RUMNavigationObservedTransitions(
            updates: updates.handleEvents(receiveOutput: { _ in receivedBySubscription.signal() }),
            acceptsDelivery: { admitted },
            destination: { value in
                projections += 1
                return .route(value)
            }
        )
        defer { observed.stop() }
        var generations: [UInt64] = []
        let observer = observed.transitions.observe { generations.append($0.generation) }
        defer { observed.transitions.removeObserver(observer) }
        let enqueued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            updates.send(1)
            enqueued.signal()
        }
        guard enqueued.wait(timeout: .now() + 5) == .success else {
            throw XCTSkip("Background source did not enqueue; delivery control is unqualified")
        }
        guard receivedBySubscription.wait(timeout: .now()) == .success else {
            XCTFail("The queued input never reached the actual subscription")
            return
        }
        admitted = false
        let drained = expectation(description: "Queued source delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 10)
        XCTAssertEqual(projections, 0)
        XCTAssertTrue(generations.isEmpty)
        updates.send(2)
        XCTAssertEqual(projections, 0)
        XCTAssertTrue(generations.isEmpty)
    }
}
#endif
#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @MainActor
    private func makeSemanticCore(directory: CoreDirectory? = nil) -> DatadogCore {
        DatadogCore(
            directory: directory ?? temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
    }

    @MainActor
    private func makeSemanticFeature(
        in core: DatadogCore,
        rows: SemanticHostRows,
        enabled: Bool = true
    ) throws -> RUMFeature {
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(
                    launchReason: .userLaunch,
                    processLaunchDate: date
                ),
                applicationStateHistory: .mockWith(
                    initialState: .active,
                    date: date
                )
            )
        }
        core.flush()
        var config = RUM.Configuration(
            applicationID: "semantic-host",
            trackAnonymousUser: false
        )
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: enabled]
        config.sessionSampleRate = 100
        config.vitalsUpdateFrequency = nil
        config.viewEventMapper = { rows.append($0); return $0 }
        config.actionEventMapper = { rows.append($0); return $0 }
        try RUM.enableOrThrow(
            with: config,
            in: core
        )
        core.flush()
        return try XCTUnwrap(core.get(feature: RUMFeature.self))
    }

    @MainActor
    private func awaitSemanticBoundary(
        _ name: String,
        core: DatadogCore?,
        condition: () -> Bool
    ) async throws {
        if let core {
            try await awaitOrdinaryBoundary(
                name,
                core: core,
                condition: condition
            )
            return
        }
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing semantic SwiftUI boundary: \(name)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(name)
    }

    @MainActor
    func testSemanticNavigationHost_whenReaderFirstAttaches_itBeginsTheSceneOwnedOccurrence() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic SwiftUI tracking requires iOS 27") }
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        let core = makeSemanticCore()
        defer { core.stop() }
        let rows = SemanticHostRows()
        let feature = try makeSemanticFeature(in: core, rows: rows)
        let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
        let source = RUMNavigationTransitions(currentDestination: .init(name: "Reader Mount"))
        let state = RUMSemanticNavigationHostState()
        let admission = try XCTUnwrap(state.configure(transitions: source, binding: binding))
        let controller = UIViewController()
        fixture.window.rootViewController = controller
        fixture.window.makeKeyAndVisible()
        let container = try XCTUnwrap(controller.view)
        let capture = SemanticReaderHandshakeCapture(state: state, source: source)
        let observer = capture.makeObserver(state: state, admission: admission)
        capture.observer = observer
        state.register(observer: observer, admission: admission)
        defer {
            observer.removeFromSuperview()
            state.finalDetach(admission: admission)
            capture.retain(in: self, fixture: fixture)
        }
        try await awaitSemanticBoundary("owned-reader-container", core: core) {
            container.window === fixture.window
        }
        capture.record("before-UIKit-attachment", proposedScene: "")
        container.addSubview(observer)
        capture.record("after-UIKit-attachment", proposedScene: fixture.identifier.rawValue)
        XCTAssertTrue(observer.window === fixture.window)
        XCTAssertEqual(observer.currentSceneIdentifier, fixture.identifier)
        XCTAssertTrue(fixture.window.rootViewController === controller)
        XCTAssertEqual(source.observationCount, 1)
        XCTAssertTrue(state.selectedTransitions === source)
        XCTAssertNotNil(state.currentIdentity)
        // Preserve a failed synchronous handshake before waiting on its mapper.
        guard source.observationCount == 1, state.currentIdentity != nil else {
            return
        }
        try await awaitSemanticBoundary("reader-scene-owned-view", core: core) {
            guard let context = feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier)),
                  let id = context.viewID else {
                return false
            }
            return context.viewName == "Reader Mount" && rows.views.contains {
                $0.view.id == id && $0.view.name == "Reader Mount" && $0.view.isActive == true
            }
        }
        let viewID = try XCTUnwrap(feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID)
        observer.removeFromSuperview()
        try await awaitSemanticBoundary("reader-owner-removal", core: core) {
            source.observationCount == 0 && state.currentIdentity == nil && rows.views.contains {
                $0.view.id == viewID && $0.view.isActive == false
            }
        }
    }

    @MainActor
    func testSemanticNavigationHost_preservesStateSourceAndActionOwnersAcrossReconstructionAndManualOverride() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic SwiftUI tracking requires iOS 27") }
        let fixture = try SemanticHostWindow()
        let core = makeSemanticCore()
        defer { core.stop() }
        let rows = SemanticHostRows()
        let feature = try makeSemanticFeature(
            in: core,
            rows: rows
        )
        var initialDestination = RUMView(
            name: "Semantic Root",
            attributes: ["source": "host"]
        )
        initialDestination.path = "semantic/root"
        let source = RUMNavigationTransitions(currentDestination: initialDestination)
        let capture = SemanticHostCapture()
        let driver = SemanticHostDriver(
            core: core,
            transitions: source
        )
        var attemptedPhase = "mount"
        var completedSchedule = false
        var observedIDs: [String: String] = [:]
        defer {
            retainSemanticHostEvidence(
                name: #function,
                phase: attemptedPhase,
                completed: completedSchedule,
                fixture: fixture,
                rows: ["current": rows],
                driver: driver,
                capture: capture,
                sources: ["selected": source],
                contexts: ["current": feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))],
                facts: ["observed_ids": observedIDs]
            )
            fixture.restore()
        }
        _ = fixture.install(SemanticHostRoot(
            driver: driver,
            capture: capture
        ))
        func snapshot() -> RUMCoreContext? {
            feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))
        }
        try await awaitSemanticBoundary(
            "semantic-root",
            core: core
        ) {
            driver.child.states == [0] && snapshot()?.viewName == "Semantic Root"
                && capture.observer?.currentSceneIdentifier == fixture.identifier
                && rows.views.contains { $0.view.id == snapshot()?.viewID && $0.view.isActive == true }
        }
        let first = try XCTUnwrap(snapshot())
        let firstID = try XCTUnwrap(first.viewID)
        observedIDs["initial"] = firstID
        XCTAssertEqual(first.viewPath, "semantic/root")
        let firstRow = try XCTUnwrap(rows.views.first { $0.view.id == firstID })
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(firstRow)
        ) as? [String: Any])
        XCTAssertEqual((encoded["context"] as? [String: Any])?["source"] as? String, "host")
        XCTAssertEqual(source.observationCount, 1)
        let updateCustomerState: () -> Void = try XCTUnwrap(driver.child.update)
        updateCustomerState()
        try await awaitSemanticBoundary(
            "customer-state",
            core: core
        ) { driver.child.states == [0, 1] }

        let offered = RUMNavigationTransitions(currentDestination: .init(name: "Unselected"))
        attemptedPhase = "source-reconstruction"
        driver.transitions = offered
        try await awaitSemanticBoundary(
            "source-reconstruction-consumed",
            core: core
        ) {
            capture.offeredSource == ObjectIdentifier(offered) && capture.readerUpdates > 1
        }
        XCTAssertTrue(capture.state?.selectedTransitions === source)
        XCTAssertEqual(driver.child.states, [0, 1])
        XCTAssertEqual(driver.child.disappearances, 0)
        XCTAssertEqual(snapshot()?.viewID, firstID)
        XCTAssertEqual(offered.observationCount, 0)
        offered.willNavigate(
            id: "ignored",
            destination: .init(name: "Still Unselected")
        )
        offered.commit(id: "ignored")
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, firstID)

        source.willNavigate(
            id: "cancel",
            destination: .init(name: "Cancelled")
        )
        source.cancel(id: "cancel")
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, firstID)
        attemptedPhase = "committed-detail"
        var detailDestination = RUMView(name: "Semantic Detail")
        detailDestination.path = "semantic/detail"
        source.willNavigate(
            id: "detail",
            destination: detailDestination
        )
        source.commit(id: "detail")
        feature.monitor.addAction(
            type: .custom,
            name: "detail-owned",
            attributes: [:],
            explicitTarget: .scene(fixture.identifier)
        )
        try await awaitSemanticBoundary(
            "committed-detail-action",
            core: core
        ) {
            rows.actions.contains { $0.action.target?.name == "detail-owned" }
        }
        let detail = try XCTUnwrap(snapshot())
        let detailID = try XCTUnwrap(detail.viewID)
        observedIDs["detail"] = detailID
        XCTAssertNotEqual(detailID, firstID)
        XCTAssertEqual(detail.viewName, "Semantic Detail")
        XCTAssertEqual(detail.sessionID, first.sessionID)
        XCTAssertEqual(rows.actions.first { $0.action.target?.name == "detail-owned" }?.view.id, detailID)

        attemptedPhase = "manual-override"
        feature.monitor.startView(
            key: "manual-host-override",
            name: "Manual Override",
            attributes: [:],
            sceneIdentifier: fixture.identifier
        )
        try await awaitSemanticBoundary(
            "manual-override",
            core: core
        ) { snapshot()?.viewName == "Manual Override" }
        let manualID = try XCTUnwrap(snapshot()?.viewID)
        observedIDs["manual"] = manualID
        source.willNavigate(
            id: "covered",
            destination: .init(name: "Covered Destination")
        )
        source.commit(id: "covered")
        feature.monitor.addAction(
            type: .custom,
            name: "manual-owned",
            attributes: [:],
            explicitTarget: .scene(fixture.identifier)
        )
        try await awaitSemanticBoundary(
            "manual-action-after-source-change",
            core: core
        ) {
            rows.actions.contains { $0.action.target?.name == "manual-owned" }
        }
        XCTAssertEqual(snapshot()?.viewID, manualID)
        XCTAssertEqual(rows.actions.first { $0.action.target?.name == "manual-owned" }?.view.id, manualID)
        attemptedPhase = "manual-reveal"
        feature.monitor.stopView(
            key: "manual-host-override",
            attributes: [:],
            sceneIdentifier: fixture.identifier
        )
        try await awaitSemanticBoundary(
            "latest-destination-revealed",
            core: core
        ) {
            snapshot()?.viewName == "Covered Destination"
        }
        var returnedDestination = RUMView(name: "Semantic Root")
        returnedDestination.path = "semantic/root"
        source.willNavigate(
            id: "return",
            destination: returnedDestination
        )
        source.commit(id: "return")
        try await awaitSemanticBoundary(
            "fresh-return",
            core: core
        ) {
            snapshot()?.viewName == "Semantic Root" && snapshot()?.viewID != firstID
        }
        let returnedID = try XCTUnwrap(snapshot()?.viewID)
        observedIDs["returned"] = returnedID
        XCTAssertNotEqual(returnedID, detailID)
        XCTAssertEqual(driver.child.states, [0, 1])
        attemptedPhase = "container-removal"
        driver.visible = false
        try await awaitSemanticBoundary(
            "host-removal",
            core: core
        ) {
            source.observationCount == 0 && snapshot()?.viewID == nil
                && rows.views.contains { $0.view.id == returnedID && $0.view.isActive == false }
        }
        source.willNavigate(
            id: "removed",
            destination: .init(name: "Removed Host")
        )
        source.commit(id: "removed")
        core.flush()
        XCTAssertNil(snapshot()?.viewID)
        XCTAssertEqual(offered.observationCount, 0)
        completedSchedule = true
    }

    @MainActor
    func testSemanticNavigationHost_whenCoreRetires_itPreservesCustomerStateAndCannotAdoptPeerOwnership() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic SwiftUI tracking requires iOS 27") }
        let fixture = try SemanticHostWindow()
        var core: DatadogCore? = makeSemanticCore()
        defer { core?.stop() }
        let originalRows = SemanticHostRows()
        let peerRows = SemanticHostRows()
        var feature: RUMFeature? = try makeSemanticFeature(
            in: XCTUnwrap(core),
            rows: originalRows
        )
        var peerCore: DatadogCore?
        var peerDirectory: CoreDirectory?
        var peerFeature: RUMFeature?
        var peerState: RUMSemanticNavigationHostState?
        var peerAdmission: RUMSwiftUIViewCallbackAdmission?
        var peerObserver: RUMSceneIdentifierReader.ObserverView?
        var expectedPeerID: String?
        var initialRetirementFacts: [String: Any] = [:]
        weak var originalCore = core
        weak var originalFeature = feature
        weak var originalFoundation = feature?.instrumentation.swiftUIViewFoundation
        let source = RUMNavigationTransitions(currentDestination: .init(name: "Original Host"))
        let capture = SemanticHostCapture()
        let driver = SemanticHostDriver(
            core: try XCTUnwrap(core),
            transitions: source
        )
        var attemptedPhase = "mount"
        var completedSchedule = false
        defer {
            retainSemanticHostEvidence(
                name: #function,
                phase: attemptedPhase,
                completed: completedSchedule,
                fixture: fixture,
                rows: ["original": originalRows, "peer": peerRows],
                driver: driver,
                capture: capture,
                sources: ["original": source],
                contexts: [
                    "original": feature?.monitor.rumContextSnapshot(for: .scene(fixture.identifier)),
                    "peer": peerFeature?.monitor.rumContextSnapshot(for: .scene(fixture.identifier))
                ],
                facts: [
                    "original_core_released": originalCore == nil, "original_feature_released": originalFeature == nil,
                    "original_foundation_released": originalFoundation == nil, "expected_peer_view": expectedPeerID ?? "",
                    "initial_delivery_retirement": initialRetirementFacts
                ]
            )
            if let peerState, let peerAdmission { peerState.finalDetach(admission: peerAdmission) }
            peerObserver?.removeFromSuperview()
            fixture.restore()
            peerCore?.stop()
            try? peerDirectory?.delete()
        }
        _ = fixture.install(SemanticHostRoot(
            driver: driver,
            capture: capture
        ))
        try await awaitSemanticBoundary(
            "original-host",
            core: core
        ) {
            feature?.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Original Host"
                && driver.child.states == [0]
        }
        try XCTUnwrap(driver.child.update)()
        try await awaitSemanticBoundary(
            "original-customer-state",
            core: core
        ) { driver.child.states == [0, 1] }

        let directory = temporaryUniqueCoreDirectory()
        peerDirectory = directory
        try directory.create()
        let peerInstance = makeSemanticCore(directory: directory)
        peerCore = peerInstance
        let peer = try makeSemanticFeature(
            in: peerInstance,
            rows: peerRows
        )
        peerFeature = peer
        let nop = NOPDatadogCore()
        attemptedPhase = "core-retirement"
        core?.stop()
        feature = nil
        core = nil
        driver.core = nop
        try await awaitSemanticBoundary(
            "retired-core-and-consumed-nop-body",
            core: peerInstance
        ) {
            originalCore == nil && originalFeature == nil && originalFoundation == nil
                && capture.configuredCore == ObjectIdentifier(nop) && capture.admission == nil
                && source.observationCount == 0
        }
        XCTAssertEqual(driver.child.states, [0, 1])
        XCTAssertEqual(driver.child.disappearances, 0)
        try XCTUnwrap(driver.child.update)()
        try await awaitSemanticBoundary(
            "customer-state-after-core-retirement",
            core: peerInstance
        ) {
            driver.child.states == [0, 1, 2]
        }

        attemptedPhase = "peer-mount"
        let binding = try XCTUnwrap(peer.instrumentation.swiftUIViewFoundation?.makeBinding())
        let peerSource = RUMNavigationTransitions(currentDestination: .init(name: "Peer Host"))
        let state = RUMSemanticNavigationHostState()
        peerState = state
        let admission = try XCTUnwrap(state.configure(
            transitions: peerSource,
            binding: binding
        ))
        peerAdmission = admission
        let observer = RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { [weak state] value in state?.reconcile(
                attachment: value,
                admission: admission
            )
            },
            onMount: { [weak state] scene in state?.readerDidMount(
                in: scene,
                admission: admission
            )
            },
            applicationSupportsMultipleScenes: true
        )
        peerObserver = observer
        state.register(
            observer: observer,
            admission: admission
        )
        fixture.window.rootViewController?.view.addSubview(observer)
        try await awaitSemanticBoundary(
            "valid-peer",
            core: peerInstance
        ) {
            peer.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Peer Host"
        }
        let peerID = try XCTUnwrap(peer.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID)
        expectedPeerID = peerID
        source.willNavigate(
            id: "late",
            destination: .init(name: "Retired Source")
        )
        source.commit(id: "late")
        peerInstance.flush()
        XCTAssertEqual(peer.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID, peerID)
        XCTAssertEqual(peerSource.observationCount, 1)
        XCTAssertEqual(source.observationCount, 0)
        XCTAssertEqual(driver.child.states, [0, 1, 2])

        // Retire a separate host while observe is still synchronously delivering
        // its initial snapshot. The returned observer token must be removed,
        // and that stale delivery must leave the live peer untouched.
        attemptedPhase = "initial-delivery-retirement"
        let retiringSource = RUMNavigationTransitions(currentDestination: .init(name: "Retired Initial"))
        let retiringState = RUMSemanticNavigationHostState()
        let retiringAdmission = try XCTUnwrap(retiringState.configure(
            transitions: retiringSource,
            binding: binding
        ))
        var retirements = 0
        retiringSource.testingBeforeInitialDelivery = { [weak retiringState, weak retiringAdmission] in
            retirements += 1
            guard let retiringState, let retiringAdmission else {
                return
            }
            retiringState.finalDetach(admission: retiringAdmission)
        }
        retiringState.reconcileInitialScene(
            fixture.identifier,
            admission: retiringAdmission
        )
        initialRetirementFacts = [
            "before_initial_delivery_callbacks": retirements,
            "source_observers": retiringSource.observationCount,
            "selected_source_released": retiringState.selectedTransitions == nil,
            "active_occurrence_absent": retiringState.currentIdentity == nil
        ]
        XCTAssertEqual(retirements, 1)
        XCTAssertEqual(retiringSource.observationCount, 0)
        XCTAssertNil(retiringState.selectedTransitions)
        XCTAssertNil(retiringState.currentIdentity)
        retiringSource.willNavigate(
            id: "late-initial",
            destination: .init(name: "Still Retired")
        )
        retiringSource.commit(id: "late-initial")
        peerInstance.flush()
        XCTAssertEqual(peer.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID, peerID)
        XCTAssertFalse(peerRows.views.contains { $0.view.name == "Retired Initial" || $0.view.name == "Still Retired" })
        completedSchedule = true
    }

    @MainActor
    func testSemanticNavigationHost_disconnectControlReleasesOnlyItsSubtreeAndRequiresReaderProofForReturn() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic SwiftUI tracking requires iOS 27") }
        let fixture = try SemanticHostWindow()
        let core = makeSemanticCore()
        defer { core.stop() }
        let rows = SemanticHostRows()
        let feature = try makeSemanticFeature(
            in: core,
            rows: rows
        )
        let source = RUMNavigationTransitions(currentDestination: .init(name: "Controlled Host"))
        let capture = SemanticHostCapture()
        let driver = SemanticHostDriver(
            core: core,
            transitions: source
        )
        var attemptedPhase = "mount"
        var completedSchedule = false
        var observedIDs: [String: String] = [:]
        var controlledSibling: UIViewController?
        var eligibilityRecords: [[String: Any]] = []
        defer {
            retainSemanticHostEvidence(
                name: #function,
                phase: attemptedPhase,
                completed: completedSchedule,
                fixture: fixture,
                rows: ["current": rows],
                driver: driver,
                capture: capture,
                sources: ["selected": source],
                contexts: ["current": feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))],
                facts: ["observed_ids": observedIDs, "eligibility": eligibilityRecords]
            )
            if let sibling = controlledSibling {
                sibling.willMove(toParent: nil)
                sibling.view.removeFromSuperview()
                sibling.removeFromParent()
            }
            fixture.restore()
        }
        let host = fixture.install(SemanticHostRoot(
            driver: driver,
            capture: capture
        ))
        let sibling = UIViewController()
        controlledSibling = sibling
        let container = try XCTUnwrap(host.parent)
        container.addChild(sibling)
        container.view.addSubview(sibling.view)
        sibling.didMove(toParent: container)
        XCTAssertTrue(sibling.parent === host.parent)
        XCTAssertFalse(sibling.view.isDescendant(of: host.view))
        func snapshot() -> RUMCoreContext? {
            feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))
        }
        try await awaitSemanticBoundary(
            "controlled-host",
            core: core
        ) {
            snapshot()?.viewName == "Controlled Host"
                && capture.observer?.currentSceneIdentifier == fixture.identifier
        }
        let state = try XCTUnwrap(capture.state)
        let admission = try XCTUnwrap(capture.admission)
        let observer = try XCTUnwrap(capture.observer)
        let foundation = try XCTUnwrap(admission.foundation)
        let eligible = try XCTUnwrap(foundation.makeEligibilityCheck())
        func eligibility(_ phase: String) -> (host: Bool,
                                              sibling: Bool) {
            let values = (host: eligible(host),
                          sibling: eligible(sibling))
            eligibilityRecords.append(["phase": phase, "host": values.host, "sibling": values.sibling])
            return values
        }
        let rootID = try XCTUnwrap(snapshot()?.viewID)
        observedIDs["initial"] = rootID
        let identity = try XCTUnwrap(state.currentIdentity)
        let mountedEligibility = eligibility("mounted")
        XCTAssertFalse(mountedEligibility.host)
        XCTAssertTrue(mountedEligibility.sibling)

        attemptedPhase = "transient-reader-remount"
        let hostingParent = try XCTUnwrap(host.view.superview)
        XCTAssertTrue(hostingParent === container.view)
        host.view.removeFromSuperview()
        hostingParent.addSubview(host.view)
        XCTAssertTrue(host.parent === container)
        // Resume after the queued detach decision, rather than requiring a
        // particular scheduling latency or treating a delay as a measurement.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, rootID)
        XCTAssertEqual(source.observationCount, 1)
        XCTAssertEqual(observer.currentSceneIdentifier, fixture.identifier)
        state.sceneDidDisconnect(
            RUMSceneIdentifier(rawValue: UUID().uuidString),
            admission: admission
        )
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, rootID)
        XCTAssertEqual(source.observationCount, 1)

        // This is a local disconnect control, not an actual OS notification.
        // The lifecycle owner performs its stop separately below.
        attemptedPhase = "local-disconnect-control"
        state.sceneDidDisconnect(
            fixture.identifier,
            admission: admission
        )
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, rootID, "The host must not duplicate the lifecycle owner's stop")
        XCTAssertEqual(source.observationCount, 0)
        let disconnectedEligibility = eligibility("local-disconnect")
        XCTAssertTrue(disconnectedEligibility.host)
        XCTAssertTrue(disconnectedEligibility.sibling)
        XCTAssertTrue(foundation.disappear(
            identity: identity,
            sceneIdentifier: fixture.identifier,
            binding: admission.binding
        ))
        try await awaitSemanticBoundary(
            "owner-stop",
            core: core
        ) { snapshot()?.viewID == nil }
        source.willNavigate(
            id: "dormant",
            destination: .init(name: "Reader Return")
        )
        source.commit(id: "dormant")
        state.reconcileInitialScene(
            fixture.identifier,
            admission: admission
        )
        core.flush()
        XCTAssertNil(snapshot()?.viewID)
        XCTAssertEqual(source.observationCount, 0)

        // Reuse the actual attached reader; an inherited trait alone was refused.
        attemptedPhase = "actual-attached-reader-return"
        observer.notifyCurrentAttachment()
        try await awaitSemanticBoundary(
            "reader-proven-return",
            core: core
        ) {
            snapshot()?.viewName == "Reader Return" && source.observationCount == 1
        }
        observedIDs["returned"] = snapshot()?.viewID
        XCTAssertNotEqual(snapshot()?.viewID, rootID)
        let returnedEligibility = eligibility("reader-return")
        XCTAssertFalse(returnedEligibility.host)
        XCTAssertTrue(returnedEligibility.sibling)
        XCTAssertEqual(Set(rows.views.filter { $0.view.name == "Controlled Host" && $0.view.isActive == false }
                            .map { $0.view.id }), [rootID])
        completedSchedule = true
    }

    @MainActor
    func testSemanticNavigationHost_whenOffNopOrCustom_itKeepsContentAndCreatesNoSemanticObserver() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Semantic SwiftUI tracking requires iOS 27") }
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        for mode in ["off", "nop", "custom"] {
            let directory = temporaryUniqueCoreDirectory()
            try directory.create()
            let realCore: DatadogCore?
            let core: DatadogCoreProtocol
            if mode == "nop" {
                realCore = nil
                core = NOPDatadogCore()
            } else {
                let instance = makeSemanticCore(directory: directory)
                realCore = instance
                core = instance
            }

            defer { realCore?.stop(); try? directory.delete() }
            let rows = SemanticHostRows()
            var feature: RUMFeature?
            let custom: RUMCommandSubscriberMock?
            if let realCore {
                feature = try makeSemanticFeature(
                    in: realCore,
                    rows: rows,
                    enabled: mode == "custom"
                )
                if mode == "custom" {
                    let subscriber = RUMCommandSubscriberMock()
                    custom = subscriber
                    let handler = try XCTUnwrap(feature?.instrumentation.viewsHandler as? RUMSceneViewsHandler)
                    handler.subscriber = subscriber
                } else {
                    custom = nil
                }
            } else {
                custom = nil
            }
            let source = RUMNavigationTransitions(currentDestination: .init(name: "Unobserved \(mode)"))
            let capture = SemanticHostCapture()
            let driver = SemanticHostDriver(
                core: core,
                transitions: source
            )
            var completedSchedule = false
            defer {
                retainSemanticHostEvidence(
                    name: #function + "-" + mode,
                    phase: mode,
                    completed: completedSchedule,
                    fixture: fixture,
                    rows: ["current": rows],
                    driver: driver,
                    capture: capture,
                    sources: ["unobserved": source],
                    contexts: [
                        "process": feature?.monitor.rumContextSnapshot(for: .processRepresentative)
                    ],
                    facts: ["mode": mode]
                )
            }
            _ = fixture.install(SemanticHostRoot(
                driver: driver,
                capture: capture,
                trackLegacyContent: true
            ))
            try await awaitSemanticBoundary(
                "consumed-\(mode)-body",
                core: realCore
            ) {
                driver.child.states == [0] && capture.configuredCore == ObjectIdentifier(core)
                    && capture.configurationUpdates > 0 && capture.admission == nil
            }
            XCTAssertEqual(source.observationCount, 0)
            XCTAssertEqual(capture.readerUpdates, 0)
            if mode == "off" {
                try await awaitSemanticBoundary(
                    "legacy-content-tracking",
                    core: realCore
                ) {
                    guard let active = feature?.monitor.activeView, let id = active.id else {
                        return false
                    }
                    return active.name == "Legacy Content" && rows.views.contains {
                        $0.view.id == id && $0.view.name == "Legacy Content" && $0.view.isActive == true
                    }
                }
            }
            try XCTUnwrap(driver.child.update)()
            try await awaitSemanticBoundary(
                "customer-state-\(mode)",
                core: realCore
            ) {
                driver.child.states == [0, 1]
            }
            XCTAssertEqual(source.observationCount, 0)
            XCTAssertFalse(rows.views.contains { $0.view.name == "Unobserved \(mode)" })
            if mode == "custom" { XCTAssertNotNil(custom) }
            withExtendedLifetime(feature) {}
            completedSchedule = true
        }
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SemanticHostCapture {
    weak var state: RUMSemanticNavigationHostState?
    weak var admission: RUMSwiftUIViewCallbackAdmission?
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    var configuredCore: ObjectIdentifier?
    var offeredSource: ObjectIdentifier?
    var configurationUpdates = 0
    var readerUpdates = 0

    func record(
        _ state: RUMSemanticNavigationHostState,
        admission: RUMSwiftUIViewCallbackAdmission?,
        observer: RUMSceneIdentifierReader.ObserverView?,
        core: ObjectIdentifier,
        offeredSource: ObjectIdentifier
    ) {
        self.state = state
        self.admission = admission
        self.configuredCore = core
        self.offeredSource = offeredSource
        if let observer {
            self.observer = observer
            readerUpdates += 1
        } else {
            configurationUpdates += 1
            if admission == nil { self.observer = nil }
        }
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SemanticReaderHandshakeCapture {
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    private weak var state: RUMSemanticNavigationHostState?
    private weak var source: RUMNavigationTransitions?
    private var callbacks: [[String: Any]] = []

    init(state: RUMSemanticNavigationHostState, source: RUMNavigationTransitions) {
        self.state = state
        self.source = source
    }

    func record(_ phase: String, proposedScene: String) {
        callbacks.append([
            "ordinal": callbacks.count, "phase": phase, "proposed_scene": proposedScene,
            "observer_identity": observer.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "actual_window": observer?.window.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "actual_scene": observer?.currentSceneIdentifier?.rawValue ?? "",
            "selected_source": state?.selectedTransitions.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "active_occurrence": state?.currentIdentity ?? "", "source_observers": source?.observationCount ?? -1
        ])
    }

    func makeObserver(
        state: RUMSemanticNavigationHostState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> RUMSceneIdentifierReader.ObserverView {
        RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { [weak state, weak admission, self] attachment in
                guard let state, let admission else {
                    return
                }
                let proposed: String
                if case .attached(let scene?) = attachment {
                    proposed = scene.rawValue
                } else {
                    proposed = ""
                }
                record("change-before", proposedScene: proposed)
                state.reconcile(attachment: attachment, admission: admission)
                record("change-after", proposedScene: proposed)
            },
            onMount: { [weak state, weak admission, self] scene in
                guard let state, let admission else {
                    return
                }
                record("mount-before", proposedScene: scene.rawValue)
                state.readerDidMount(in: scene, admission: admission)
                record("mount-after", proposedScene: scene.rawValue)
            },
            applicationSupportsMultipleScenes: true
        )
    }

    func retain(in test: XCTestCase, fixture: SemanticHostWindow) {
        let payload: [String: Any] = [
            "schema_version": 1, "family": "semantic-navigation-reader-handshake",
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "scene_identifier": fixture.identifier.rawValue,
            "owned_window": String(describing: ObjectIdentifier(fixture.window)),
            "callbacks": callbacks,
            "scope": "Reader/host first-attachment discriminator; no rendered SwiftUI or release-gate credit"
        ]
        do {
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: payload),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "semantic-navigation-reader-handshake"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        } catch {
            XCTFail("Could not retain reader mount observations")
        }
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SemanticHostDriver: ObservableObject {
    @Published var core: DatadogCoreProtocol
    @Published var transitions: RUMNavigationTransitions
    @Published var visible = true
    let child = OrdinarySwiftUIViewDriver()

    init(core: DatadogCoreProtocol,
         transitions: RUMNavigationTransitions) {
        self.core = core
        self.transitions = transitions
    }
}

@available(iOS 27.0, *)
@MainActor
private struct SemanticHostRoot: View {
    @ObservedObject var driver: SemanticHostDriver
    let capture: SemanticHostCapture
    var trackLegacyContent = false

    var body: some View {
        let source = driver.transitions
        let core = driver.core
        let coreIdentity = ObjectIdentifier(core)
        let sourceIdentity = ObjectIdentifier(source)
        return Group {
            if driver.visible {
                RUMNavigationHost(
                    transitions: source,
                    in: core,
                    testingOnHostUpdate: { state, admission, observer in
                        capture.record(
                            state,
                            admission: admission,
                            observer: observer,
                            core: coreIdentity,
                            offeredSource: sourceIdentity
                        )
                    }
                ) {
                    if trackLegacyContent {
                        OrdinarySwiftUIViewChild(driver: driver.child)
                            .trackRUMView(
                                name: "Legacy Content",
                                in: core
                            )
                    } else {
                        OrdinarySwiftUIViewChild(driver: driver.child)
                    }
                }
            }
        }
    }
}

private final class SemanticHostRows: @unchecked Sendable {
    private let lock = NSLock()
    private var viewValues: [RUMViewEvent] = []
    private var actionValues: [RUMActionEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; viewValues.append(value) }
    func append(_ value: RUMActionEvent) { lock.lock(); defer { lock.unlock() }; actionValues.append(value) }
    var views: [RUMViewEvent] { lock.lock(); defer { lock.unlock() }; return viewValues }
    var actions: [RUMActionEvent] { lock.lock(); defer { lock.unlock() }; return actionValues }
}

@MainActor
private final class SemanticHostWindow {
    let scene: UIWindowScene
    let window: UIWindow
    let identifier: RUMSceneIdentifier
    private let originalRoot: UIViewController
    private let originalHidden: Bool
    private let originalKey: UIWindow?

    init() throws {
        let expected = try XCTUnwrap(NSClassFromString("Example.MountedWebViewSceneDelegate"))
        let owned = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState != .unattached && $0.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expected)
            } == true
        }
        XCTAssertEqual(owned.count, 1)
        scene = try XCTUnwrap(owned.first)
        let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
        window = try XCTUnwrap(delegate.window ?? nil)
        originalRoot = try XCTUnwrap(window.rootViewController)
        originalHidden = window.isHidden
        originalKey = scene.windows.first(where: \.isKeyWindow)
        identifier = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        XCTAssertTrue(window.windowScene === scene && scene.windows.contains { $0 === window })
        XCTAssertTrue(window.bounds.width.isFinite && window.bounds.height.isFinite
                        && window.bounds.width > 0 && window.bounds.height > 0)
    }

    func install<Content: View>(_ content: Content) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        let container = UIViewController()
        window.rootViewController = container
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()
        XCTAssertTrue(window.rootViewController === container && window.windowScene === scene)
        XCTAssertTrue(host.parent === container && host.view.superview === container.view)
        return host
    }

    func restore() {
        window.rootViewController = originalRoot
        window.isHidden = originalHidden
        originalKey?.makeKey()
    }
}
#endif
#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @available(iOS 27.0, *)
    @MainActor
    private func retainSemanticHostEvidence(
        name: String,
        phase: String,
        completed: Bool,
        fixture: SemanticHostWindow,
        rows: [String: SemanticHostRows],
        driver: SemanticHostDriver,
        capture: SemanticHostCapture,
        sources: [String: RUMNavigationTransitions],
        contexts: [String: RUMCoreContext?],
        facts: [String: Any]
    ) {
        do {
            let eventRows = try rows.mapValues { values -> [String: Any] in
                [
                    "views": try values.views.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    },
                    "actions": try values.actions.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    }
                ]
            }
            let contextRows = contexts.mapValues { value -> [String: String] in
                value.map {
                    [
                        "session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                        "name": $0.viewName ?? "", "path": $0.viewPath ?? ""
                    ]
                } ?? [:]
            }
            let windows: [[String: Any]] = fixture.scene.windows.map { window in
                [
                    "identity": String(describing: ObjectIdentifier(window)),
                    "fixture_delegate_window": window === fixture.window,
                    "key": window.isKeyWindow, "hidden": window.isHidden,
                    "width": Double(window.bounds.width), "height": Double(window.bounds.height),
                    "scene_matches": window.windowScene === fixture.scene
                ]
            }
            let payload: [String: Any] = [
                "schema_version": 1, "family": "private-semantic-navigation-host",
                "case": name, "attempted_phase": phase, "completed_schedule": completed,
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "scene_identifier": fixture.identifier.rawValue,
                "scene_activation": fixture.scene.activationState.rawValue,
                "application_state": UIApplication.shared.applicationState.rawValue,
                "window_inventory": windows,
                "root_identity": fixture.window.rootViewController.map {
                    String(describing: ObjectIdentifier($0))
                } ?? "",
                "customer_states": driver.child.states,
                "customer_disappearances": driver.child.disappearances,
                "source_observer_counts": sources.mapValues { $0.observationCount },
                "configuration_receipts": capture.configurationUpdates,
                "reader_receipts": capture.readerUpdates,
                "admission_valid": capture.admission?.isValid == true,
                "reader_scene": capture.observer?.currentSceneIdentifier?.rawValue ?? "",
                "contexts": contextRows, "event_rows": eventRows, "facts": facts,
                "scope": "Source/component control; no actual OS disconnect, automatic-input or release-gate credit"
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: payload),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "semantic-navigation-host-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not retain semantic navigation host observations")
        }
    }
}
#endif
#if os(iOS) && canImport(SwiftUI) && compiler(>=6.4) && canImport(Observation)
import Observation

extension SwiftUINavigationOwnershipTests {
    @MainActor
    func testObservedNavigationHost_whenCommittedStateChanges_itPublishesTheAcceptedOwner() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Observed navigation requires iOS 27") }
        for mode in ObservedHostMode.allCases {
            let fixture = try SemanticHostWindow()
            let core = makeSemanticCore()
            let rows = SemanticHostRows()
            let feature = try makeSemanticFeature(in: core, rows: rows)
            let driver = ObservedHostDriver(core: core, mode: mode)
            let capture = ObservedHostCapture()
            var phase = "initial"
            var completed = false
            var ids: [String: String] = [:]
            defer {
                retainObservedHostEvidence(
                    name: #function + "-" + mode.rawValue,
                    phase: phase,
                    completed: completed,
                    fixture: fixture,
                    rows: rows,
                    driver: driver,
                    capture: capture,
                    facts: ids
                )
                fixture.restore()
                core.stop()
            }
            _ = fixture.install(ObservedHostRoot(driver: driver, capture: capture))
            func snapshot() -> RUMCoreContext? {
                feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))
            }
            try await awaitSemanticBoundary("observed-initial-" + mode.rawValue, core: core) {
                snapshot()?.viewName == "Home" && driver.child.states == [0]
                    && capture.observer?.currentSceneIdentifier == fixture.identifier
                    && rows.views.contains { $0.view.id == snapshot()?.viewID && $0.view.isActive == true }
            }
            let first = try XCTUnwrap(snapshot())
            ids["home"] = try XCTUnwrap(first.viewID)
            let source = try XCTUnwrap(capture.state?.selectedTransitions)
            var generations: [UInt64] = []
            let token = source.observe { generations.append($0.generation) }
            defer { source.removeObserver(token) }
            XCTAssertEqual(generations, [0])
            XCTAssertEqual(source.observationCount, 2)
            XCTAssertEqual(driver.subscriptions, mode == .publisher ? 1 : 0)
            try XCTUnwrap(driver.child.update)()
            try await awaitSemanticBoundary("observed-customer-state", core: core) {
                driver.child.states == [0, 1]
            }

            phase = "reconstruction"
            let updatesBefore = capture.updates
            let replacement = ObservedHostInput(initial: .root(ObservedHostRoute.replacement))
            var replacementSubscriptions = 0
            driver.offeredPublisher = replacement.publisher.handleEvents(receiveSubscription: { _ in
                replacementSubscriptions += 1
            })
            .eraseToAnyPublisher()
            driver.revision += 1
            try await awaitSemanticBoundary("observed-reconstruction", core: core) {
                capture.updates > updatesBefore && capture.revision == driver.revision
            }
            XCTAssertTrue(capture.state?.selectedTransitions === source)
            XCTAssertEqual(snapshot()?.viewID, first.viewID)
            XCTAssertEqual(replacementSubscriptions, 0)
            XCTAssertEqual(driver.subscriptions, mode == .publisher ? 1 : 0)
            XCTAssertEqual(driver.child.states, [0, 1])
            XCTAssertEqual(driver.child.disappearances, 0)

            phase = "accepted-equal-occurrences"
            let secret = "associated-value-stays-local"
            for occurrence in [1, 2] {
                driver.accept(.route(ObservedHostRoute.detail(secret: secret), occurrence: occurrence))
                // Ordering is semantic: the committed source changes before the
                // setter/send returns, without a duration measurement.
                XCTAssertEqual(generations.last, UInt64(occurrence))
                feature.monitor.addAction(
                    type: .custom,
                    name: "accepted-\(occurrence)",
                    attributes: [:],
                    explicitTarget: .scene(fixture.identifier)
                )
                try await awaitSemanticBoundary("observed-action-\(occurrence)", core: core) {
                    rows.actions.contains { $0.action.target?.name == "accepted-\(occurrence)" }
                }
                let current = try XCTUnwrap(snapshot())
                let id = try XCTUnwrap(current.viewID)
                XCTAssertEqual(current.viewName, "Detail")
                XCTAssertEqual(current.sessionID, first.sessionID)
                XCTAssertEqual(rows.actions.first {
                    $0.action.target?.name == "accepted-\(occurrence)"
                }?.view.id, id)
                XCTAssertFalse(ids.values.contains(id))
                ids["detail-\(occurrence)"] = id
            }
            phase = "fresh-return"
            driver.accept(.root(ObservedHostRoute.home))
            XCTAssertEqual(generations, [0, 1, 2, 3])
            try await awaitSemanticBoundary("observed-fresh-return", core: core) {
                snapshot()?.viewName == "Home" && snapshot()?.viewID != first.viewID
            }
            ids["returned"] = try XCTUnwrap(snapshot()?.viewID)
            XCTAssertFalse(ids.filter { $0.key != "returned" }.values.contains(ids["returned"] ?? ""))
            XCTAssertEqual(driver.child.states, [0, 1])
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(rows.views), as: UTF8.self).contains(secret))
            phase = "nested-accepted-mutation"
            var reentered = false
            let nested = source.observe { value in
                if value.generation == 4, !reentered {
                    reentered = true
                    driver.accept(.root(ObservedHostRoute.home))
                }
            }
            driver.accept(.route(ObservedHostRoute.detail(secret: secret), occurrence: 3))
            source.removeObserver(nested)
            XCTAssertTrue(reentered)
            XCTAssertEqual(generations.last, 5)
            feature.monitor.addAction(
                type: .custom,
                name: "nested-accepted-owner",
                attributes: [:],
                explicitTarget: .scene(fixture.identifier)
            )
            try await awaitSemanticBoundary("observed-nested-owner", core: core) {
                snapshot()?.viewName == "Home" && snapshot()?.viewID != ids["returned"]
                    && rows.actions.contains { $0.action.target?.name == "nested-accepted-owner" }
            }
            XCTAssertEqual(rows.actions.first {
                $0.action.target?.name == "nested-accepted-owner"
            }?.view.id, snapshot()?.viewID)
            phase = "local-disconnect-and-reader-return"
            let state = try XCTUnwrap(capture.state)
            let admission = try XCTUnwrap(capture.admission)
            let observer = try XCTUnwrap(capture.observer)
            let identity = try XCTUnwrap(state.currentIdentity)
            let beforeDisconnect = try XCTUnwrap(snapshot()?.viewID)
            state.sceneDidDisconnect(fixture.identifier, admission: admission)
            XCTAssertEqual(source.observationCount, 1)
            XCTAssertEqual(driver.cancellations, mode == .publisher ? 1 : 0)
            // This is the existing local component control. The lifecycle
            // owner stops the old occurrence; no actual OS disconnect is claimed.
            XCTAssertEqual(admission.foundation?.disappear(
                identity: identity,
                sceneIdentifier: fixture.identifier,
                binding: admission.binding
            ), true)
            try await awaitSemanticBoundary("observed-disconnect-owner-stop", core: core) {
                snapshot()?.viewID == nil
            }
            driver.accept(.root(ObservedHostRoute.home))
            state.reconcileInitialScene(fixture.identifier, admission: admission)
            core.flush()
            XCTAssertNil(snapshot()?.viewID)
            XCTAssertEqual(source.observationCount, 1)
            observer.notifyCurrentAttachment()
            try await awaitSemanticBoundary("observed-reader-proven-return", core: core) {
                snapshot()?.viewName == "Home" && snapshot()?.viewID != beforeDisconnect
                    && state.selectedTransitions != nil && state.selectedTransitions !== source
            }
            let returnedSource = try XCTUnwrap(state.selectedTransitions)
            XCTAssertEqual(returnedSource.observationCount, 1)
            XCTAssertEqual(driver.subscriptions, mode == .publisher ? 2 : 0)
            XCTAssertEqual(replacementSubscriptions, 0)
            ids["reader-return"] = try XCTUnwrap(snapshot()?.viewID)
            phase = "removal"
            driver.visible = false
            try await awaitSemanticBoundary("observed-removal", core: core) {
                returnedSource.observationCount == 0 && snapshot()?.viewID == nil
                    && (mode != .publisher || driver.cancellations == 2)
            }
            let before = generations
            driver.accept(.root(ObservedHostRoute.replacement))
            core.flush()
            XCTAssertEqual(generations, before)
            XCTAssertNil(snapshot()?.viewID)
            XCTAssertEqual(replacementSubscriptions, 0)
            completed = true
        }

        // A configured empty stream pins its input without seizing authority.
        let fixture = try SemanticHostWindow()
        let core = makeSemanticCore()
        defer { fixture.restore(); core.stop() }
        let rows = SemanticHostRows()
        let feature = try makeSemanticFeature(in: core, rows: rows)
        let driver = ObservedHostDriver(core: core, mode: .publisher, empty: true)
        let capture = ObservedHostCapture()
        var completed = false
        defer {
            retainObservedHostEvidence(
                name: #function + "-empty",
                phase: "empty-source",
                completed: completed,
                fixture: fixture,
                rows: rows,
                driver: driver,
                capture: capture,
                facts: [:]
            )
        }
        _ = fixture.install(ObservedHostRoot(driver: driver, capture: capture))
        try await awaitSemanticBoundary("empty-observed-input", core: core) {
            capture.observer?.currentSceneIdentifier == fixture.identifier
                && capture.state?.selectedTransitions != nil && driver.subscriptions == 1
        }
        XCTAssertNil(capture.state?.currentIdentity)
        XCTAssertEqual(capture.admission?.withSession { $0.suppressionState.isActive }, false)
        let replacement = ObservedHostInput(initial: .root(ObservedHostRoute.replacement))
        var replacementSubscriptions = 0
        driver.offeredPublisher = replacement.publisher.handleEvents(receiveSubscription: { _ in
            replacementSubscriptions += 1
        })
        .eraseToAnyPublisher()
        driver.revision += 1
        try await awaitSemanticBoundary("empty-source-reconstruction-consumed", core: core) {
            capture.revision == driver.revision
        }
        driver.accept(.root(ObservedHostRoute.home))
        try await awaitSemanticBoundary("first-accepted-empty-input", core: core) {
            feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Home"
        }
        XCTAssertEqual(driver.subscriptions, 1)
        XCTAssertEqual(replacementSubscriptions, 0)
        completed = true
    }

    @MainActor
    func testObservedNavigationHost_whenOriginalAdmissionRetires_itRejectsQueuedApplicationCallbacks() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Observed navigation requires iOS 27") }
        for mode in ObservedHostMode.allCases {
            let fixture = try SemanticHostWindow()
            let core = makeSemanticCore()
            let rows = SemanticHostRows()
            let feature = try makeSemanticFeature(in: core, rows: rows)
            let receipt = DispatchSemaphore(value: 0)
            let driver = ObservedHostDriver(core: core, mode: mode, queuedReceipt: receipt)
            let capture = ObservedHostCapture()
            let peerDirectory = temporaryUniqueCoreDirectory()
            try peerDirectory.create()
            var peerCore: DatadogCore?
            var completed = false
            defer {
                retainObservedHostEvidence(
                    name: #function + "-" + mode.rawValue,
                    phase: "retirement",
                    completed: completed,
                    fixture: fixture,
                    rows: rows,
                    driver: driver,
                    capture: capture,
                    facts: [:]
                )
                fixture.restore()
                peerCore?.stop()
                core.stop()
                try? peerDirectory.delete()
            }
            _ = fixture.install(ObservedHostRoot(driver: driver, capture: capture))
            try await awaitSemanticBoundary("observed-original-owner", core: core) {
                feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Home"
                    && driver.child.states == [0]
            }
            let originalSource = try XCTUnwrap(capture.state?.selectedTransitions)
            let originalAdmission = try XCTUnwrap(capture.admission)
            let projections = driver.projections
            if mode == .publisher {
                let input = driver.input
                let sent = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    input.send(.route(
                        ObservedHostRoute.detail(secret: "queued"),
                        occurrence: 1,
                        attributes: ["queued-probe": true]
                    ))
                    sent.signal()
                }
                XCTAssertEqual(sent.wait(timeout: .now() + 5), .success)
                // Only the marked queued input signals this receipt. Initial
                // readiness cannot consume or stand in for this boundary.
                XCTAssertEqual(receipt.wait(timeout: .now()), .success)
            }
            core.stop()
            XCTAssertFalse(originalAdmission.isValid)
            driver.core = NOPDatadogCore()
            if mode == .observation {
                driver.accept(.route(ObservedHostRoute.detail(secret: "retired"), occurrence: 1))
            }
            let drained = expectation(description: "Original queued delivery drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 10)
            try await awaitSemanticBoundary("retired-observed-host", core: nil) {
                capture.admission == nil && originalSource.observationCount == 0
            }
            XCTAssertEqual(driver.projections, projections)
            XCTAssertNil(capture.state?.currentIdentity)
            XCTAssertEqual(driver.child.states, [0])
            XCTAssertEqual(driver.child.disappearances, 0)

            let peer = makeSemanticCore(directory: peerDirectory)
            peerCore = peer
            let peerRows = SemanticHostRows()
            let peerFeature = try makeSemanticFeature(in: peer, rows: peerRows)
            let peerDriver = ObservedHostDriver(core: peer, mode: mode)
            let peerCapture = ObservedHostCapture()
            _ = fixture.install(ObservedHostRoot(driver: peerDriver, capture: peerCapture))
            try await awaitSemanticBoundary("observed-peer-owner", core: peer) {
                peerFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Home"
            }
            let peerID = try XCTUnwrap(peerFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID)
            driver.accept(.root(ObservedHostRoute.replacement))
            peerFeature.monitor.addAction(
                type: .custom,
                name: "peer-after-retirement",
                attributes: [:],
                explicitTarget: .scene(fixture.identifier)
            )
            try await awaitSemanticBoundary("observed-peer-action", core: peer) {
                peerRows.actions.contains { $0.action.target?.name == "peer-after-retirement" }
            }
            XCTAssertEqual(peerRows.actions.first {
                $0.action.target?.name == "peer-after-retirement"
            }?.view.id, peerID)
            XCTAssertEqual(driver.projections, projections)
            XCTAssertEqual(originalSource.observationCount, 0)
            retainObservedHostEvidence(
                name: #function + "-" + mode.rawValue + "-peer",
                phase: "peer-ownership",
                completed: true,
                fixture: fixture,
                rows: peerRows,
                driver: peerDriver,
                capture: peerCapture,
                facts: ["peer": peerID]
            )
            completed = true
        }

        // Initial synchronous delivery can retire the host before the source
        // factory returns. Its returned subscription must still be cancelled.
        do {
            let core = makeSemanticCore()
            defer { core.stop() }
            let rows = SemanticHostRows()
            let feature = try makeSemanticFeature(in: core, rows: rows)
            let binding = try XCTUnwrap(feature.instrumentation.swiftUIViewFoundation?.makeBinding())
            let state = RUMSemanticNavigationHostState()
            let input = ObservedHostInput(initial: .root(ObservedHostRoute.home))
            var subscriptions = 0
            var cancellations = 0
            var projections = 0
            var returned: RUMNavigationObservedTransitions?
            let factory = RUMNavigationHostInput.observing { acceptsDelivery in
                let source = RUMNavigationObservedTransitions(
                    updates: input.publisher.handleEvents(receiveSubscription: { _ in
                        subscriptions += 1
                    }, receiveCancel: { cancellations += 1 }),
                    acceptsDelivery: acceptsDelivery,
                    destination: { value in
                        projections += 1
                        _ = state.configure(input: .automatic, binding: nil)
                        return value
                    }
                )
                returned = source
                return source
            }
            XCTAssertNil(state.configure(input: factory, binding: binding))
            XCTAssertEqual(subscriptions, 1)
            XCTAssertEqual(cancellations, 1)
            XCTAssertEqual(projections, 1)
            XCTAssertNil(state.selectedTransitions)
            XCTAssertNil(state.currentIdentity)
            XCTAssertEqual(returned?.transitions.observationCount, 0)
            input.send(.root(ObservedHostRoute.replacement))
            XCTAssertEqual(projections, 1)
            let facts: [String: Any] = [
                "family": "observed-host-initial-factory-retirement",
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "subscriptions": subscriptions,
                "cancellations": cancellations,
                "projections": projections,
                "selected_source_absent": state.selectedTransitions == nil,
                "occurrence_absent": state.currentIdentity == nil
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: facts),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "observed-host-initial-factory-retirement"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // Both newly exposed adapter constructors stay lazy on the existing
        // Off/custom/NOP paths; content-only keeps its ordinary tracking calls.
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        for mode in ObservedHostMode.allCases {
            for path in ["off", "custom", "nop", "content-only"] {
                let directory = temporaryUniqueCoreDirectory()
                try directory.create()
                let real = path == "nop" ? nil : makeSemanticCore(directory: directory)
                defer { real?.stop(); try? directory.delete() }
                let rows = SemanticHostRows()
                var feature: RUMFeature?
                var custom: RUMCommandSubscriberMock?
                if let real {
                    feature = try makeSemanticFeature(
                        in: real,
                        rows: rows,
                        enabled: path == "custom" || path == "content-only"
                    )
                    if path == "custom" {
                        let subscriber = RUMCommandSubscriberMock()
                        custom = subscriber
                        try XCTUnwrap(feature?.instrumentation.viewsHandler as? RUMSceneViewsHandler).subscriber = subscriber
                    }
                }
                let selectedCore: DatadogCoreProtocol
                if let real {
                    selectedCore = real
                } else {
                    selectedCore = NOPDatadogCore()
                }
                let driver = ObservedHostDriver(core: selectedCore, mode: mode)
                driver.contentOnly = path == "content-only"
                driver.trackLegacyContent = true
                let capture = ObservedHostCapture()
                var completed = false
                defer {
                    retainObservedHostEvidence(
                        name: #function + "-" + mode.rawValue + "-" + path,
                        phase: path,
                        completed: completed,
                        fixture: fixture,
                        rows: rows,
                        driver: driver,
                        capture: capture,
                        facts: [:]
                    )
                }
                _ = fixture.install(ObservedHostRoot(driver: driver, capture: capture))
                try await awaitSemanticBoundary("observed-unused-" + path, core: real) {
                    driver.child.states == [0] && capture.updates > 0
                }
                XCTAssertEqual(driver.projections, 0)
                XCTAssertEqual(driver.subscriptions, 0)
                XCTAssertNil(capture.state?.selectedTransitions)
                if path == "off" || path == "content-only" {
                    try await awaitSemanticBoundary("observed-legacy-content-" + path, core: real) {
                        let activeID: String?
                        if path == "off" {
                            activeID = feature?.monitor.activeView.id
                        } else {
                            activeID = feature?.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID
                        }
                        return activeID != nil && rows.views.contains {
                            $0.view.id == activeID && $0.view.name == "Observed Legacy Content" && $0.view.isActive == true
                        }
                    }
                }
                try XCTUnwrap(driver.child.update)()
                try await awaitSemanticBoundary("observed-unused-customer-state", core: real) {
                    driver.child.states == [0, 1]
                }
                XCTAssertEqual(driver.projections, 0)
                XCTAssertEqual(driver.subscriptions, 0)
                if path == "custom" { XCTAssertNotNil(custom) }
                completed = true
            }
        }
    }

    @available(iOS 27.0, *)
    @MainActor
    private func retainObservedHostEvidence(
        name: String,
        phase: String,
        completed: Bool,
        fixture: SemanticHostWindow,
        rows: SemanticHostRows,
        driver: ObservedHostDriver,
        capture: ObservedHostCapture,
        facts: [String: String]
    ) {
        do {
            let views = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows.views))
            let actions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows.actions))
            let value: [String: Any] = [
                "family": "accepted-state-host-adapters",
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "variant": driver.mode.rawValue,
                "phase": phase,
                "completed": completed,
                "scene_identifier": fixture.identifier.rawValue,
                "owned_window": String(describing: ObjectIdentifier(fixture.window)),
                "actual_window_scene": fixture.window.windowScene?.session.persistentIdentifier ?? "",
                "reader_scene": capture.observer?.currentSceneIdentifier?.rawValue ?? "",
                "subscriptions": driver.subscriptions,
                "cancellations": driver.cancellations,
                "projections": driver.projections,
                "host_updates": capture.updates,
                "selected_source": capture.state?.selectedTransitions.map { String(describing: ObjectIdentifier($0)) } ?? "",
                "customer_states": driver.child.states,
                "customer_disappearances": driver.child.disappearances,
                "views": views,
                "actions": actions,
                "facts": facts
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: value),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not retain observed-host evidence")
        }
    }
}

private enum ObservedHostRoute: Hashable {
    case home
    case detail(secret: String)
    case replacement
}

private enum ObservedHostMode: String, CaseIterable {
    case publisher
    case observation
}

/// Combine subjects serialize delivery; the fixtures publish immutable values.
@available(iOS 27.0, *)
private final class ObservedHostInput: @unchecked Sendable {
    private let subject: CurrentValueSubject<RUMNavigationDestination?, Never>

    init(initial: RUMNavigationDestination?) {
        subject = CurrentValueSubject(initial)
    }

    var publisher: AnyPublisher<RUMNavigationDestination, Never> {
        subject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func send(_ destination: RUMNavigationDestination) {
        subject.send(destination)
    }
}

@available(iOS 27.0, *)
@MainActor
@Observable
private final class ObservedHostRouter {
    var accepted: RUMNavigationDestination = .root(ObservedHostRoute.home)
}

@available(iOS 27.0, *)
@MainActor
private final class ObservedHostDriver: ObservableObject {
    @Published var core: DatadogCoreProtocol
    @Published var visible = true
    @Published var revision = 0
    let mode: ObservedHostMode
    let input: ObservedHostInput
    let router = ObservedHostRouter()
    let child = OrdinarySwiftUIViewDriver()
    var offeredPublisher: AnyPublisher<RUMNavigationDestination, Never>
    var projections = 0
    var subscriptions = 0
    var cancellations = 0
    var contentOnly = false
    var trackLegacyContent = false

    init(
        core: DatadogCoreProtocol,
        mode: ObservedHostMode,
        empty: Bool = false,
        queuedReceipt: DispatchSemaphore? = nil
    ) {
        self.core = core
        self.mode = mode
        let input = ObservedHostInput(initial: empty ? nil : .root(ObservedHostRoute.home))
        self.input = input
        offeredPublisher = input.publisher
        offeredPublisher = input.publisher.handleEvents(receiveSubscription: { [weak self] _ in
            self?.subscriptions += 1
        }, receiveOutput: { destination in
            if destination.attributes["queued-probe"] as? Bool == true {
                queuedReceipt?.signal()
            }
        }, receiveCancel: { [weak self] in
            self?.cancellations += 1
        })
        .eraseToAnyPublisher()
    }

    func accept(_ destination: RUMNavigationDestination) {
        switch mode {
        case .publisher: input.send(destination)
        case .observation: router.accepted = destination
        }
    }

    func project(_ destination: RUMNavigationDestination) -> RUMNavigationDestination {
        projections += 1
        return destination
    }
}

@available(iOS 27.0, *)
@MainActor
private final class ObservedHostCapture {
    weak var state: RUMSemanticNavigationHostState?
    weak var admission: RUMSwiftUIViewCallbackAdmission?
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    var updates = 0
    var revision = -1

    func record(
        _ state: RUMSemanticNavigationHostState,
        admission: RUMSwiftUIViewCallbackAdmission?,
        observer: RUMSceneIdentifierReader.ObserverView?,
        revision: Int
    ) {
        self.state = state
        self.admission = admission
        if let observer { self.observer = observer }
        self.revision = revision
        updates += 1
    }
}

@available(iOS 27.0, *)
@MainActor
private struct ObservedHostRoot: View {
    @ObservedObject var driver: ObservedHostDriver
    let capture: ObservedHostCapture

    @ViewBuilder private var content: some View {
        if driver.trackLegacyContent {
            OrdinarySwiftUIViewChild(driver: driver.child)
                .trackRUMView(name: "Observed Legacy Content", in: driver.core)
        } else {
            OrdinarySwiftUIViewChild(driver: driver.child)
        }
    }

    @ViewBuilder var body: some View {
        if driver.visible {
            let revision = driver.revision
            if driver.contentOnly {
                RUMNavigationHost(in: driver.core) { content }
                    .withTestingOnHostUpdate { state, admission, observer in
                        capture.record(state, admission: admission, observer: observer, revision: revision)
                    }
            } else if driver.mode == .publisher {
                RUMNavigationHost(
                    observing: driver.offeredPublisher,
                    destination: { driver.project($0) },
                    in: driver.core
                ) { content }
                    .withTestingOnHostUpdate { state, admission, observer in
                        capture.record(state, admission: admission, observer: observer, revision: revision)
                    }
            } else {
                RUMNavigationHost(observingCurrentDestination: {
                    driver.project(driver.router.accepted)
                }, in: driver.core) { content }
                .withTestingOnHostUpdate { state, admission, observer in
                    capture.record(state, admission: admission, observer: observer, revision: revision)
                }
            }
        }
    }
}
@MainActor
extension SwiftUINavigationOwnershipTests {
    func testNativeNavigationStack_whenAcceptedPathChanges_itTracksMaterializedOccurrences() async throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native semantic navigation requires iOS 27")
        }
        let fixture = try SemanticHostWindow()
        let core = makeSemanticCore()
        let rows = SemanticHostRows()
        let feature = try makeSemanticFeature(in: core, rows: rows)
        let driver = NativeHostDriver(core: core)
        let capture = NativeHostCapture()
        let previousHook = RUMNativeNavigationTesting.onBoundary
        capture.observeBoundaries()
        defer { RUMNativeNavigationTesting.onBoundary = previousHook }
        var phase = "root"
        var completed = false
        var ids: [String] = []
        defer {
            retainNativeHostEvidence(
                phase: phase,
                completed: completed,
                fixture: fixture,
                rows: rows,
                driver: driver,
                capture: capture,
                ids: ids
            )
            fixture.restore()
            core.stop()
        }
        _ = fixture.install(NativeHostRoot(driver: driver, capture: capture))
        func snapshot() -> RUMCoreContext? {
            feature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))
        }
        try await awaitSemanticBoundary("native-root", core: core) {
            snapshot()?.viewName == "Root" && driver.child.states == [0]
                && capture.observer?.currentSceneIdentifier == fixture.identifier
                && rows.views.contains { $0.view.id == snapshot()?.viewID && $0.view.isActive == true }
        }
        try await awaitSemanticBoundary("native-root-reader", core: core) {
            capture.proof(viewID: snapshot()?.viewID, depth: 0, fixture: fixture, rows: rows) != nil
        }
        capture.proofs.append(try XCTUnwrap(capture.proof(viewID: snapshot()?.viewID, depth: 0, fixture: fixture, rows: rows)))
        let session = try XCTUnwrap(snapshot()?.sessionID)
        ids.append(try XCTUnwrap(snapshot()?.viewID))
        try XCTUnwrap(driver.child.update)()
        try await awaitSemanticBoundary("native-customer-state", core: core) {
            driver.child.states.last == 1
        }

        phase = "rejected-binding-proposal"
        driver.acceptsProposals = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        try XCTUnwrap(capture.path).transaction(transaction).wrappedValue = [.detail(secret: "rejected")]
        XCTAssertEqual(driver.path, [])
        XCTAssertEqual(driver.forwardedTransactions.last, true)
        core.flush()
        XCTAssertEqual(snapshot()?.viewID, ids.last)
        XCTAssertFalse(rows.views.contains { $0.view.name == "Detail" })
        driver.acceptsProposals = true

        let secret = "native-associated-value-stays-local"
        for depth in [1, 2] {
            phase = "accepted-depth-\(depth)"
            try XCTUnwrap(capture.path).wrappedValue = Array(repeating: .detail(secret: secret), count: depth)
            try await awaitSemanticBoundary("native-depth-\(depth)", core: core) {
                driver.materializedDepths.contains(depth) && snapshot()?.viewName == "Detail"
                    && snapshot()?.viewID != ids.last
                    && rows.views.contains { $0.view.id == snapshot()?.viewID && $0.view.isActive == true }
            }
            try await awaitSemanticBoundary("native-reader-depth-\(depth)", core: core) {
                capture.proof(viewID: snapshot()?.viewID, depth: depth, fixture: fixture, rows: rows) != nil
            }
            capture.proofs.append(try XCTUnwrap(capture.proof(viewID: snapshot()?.viewID, depth: depth, fixture: fixture, rows: rows)))
            let id = try XCTUnwrap(snapshot()?.viewID)
            XCTAssertFalse(ids.contains(id))
            XCTAssertEqual(snapshot()?.sessionID, session)
            ids.append(id)
            if depth == 2 {
                // Keep the real outgoing state alive through the retained reveal.
                let outgoing = try XCTUnwrap(capture.boundaries.first {
                    $0.state?.activeLifecycleGeneration != nil
                        && $0.state?.configuration?.descriptor.attributes["native_test_depth"] as? Int == 2
                }?.state)
                capture.retainedOutgoingStates.append(outgoing)
            }
            feature.monitor.addAction(
                type: .custom,
                name: "native-owned-\(depth)",
                attributes: [:],
                explicitTarget: .scene(fixture.identifier)
            )
            try await awaitSemanticBoundary("native-action-\(depth)", core: core) {
                rows.actions.contains { $0.action.target?.name == "native-owned-\(depth)" }
            }
            XCTAssertEqual(rows.actions.first { $0.action.target?.name == "native-owned-\(depth)" }?.view.id, id)
        }

        for depth in [1, 0] {
            phase = "reveal-depth-\(depth)"
            try XCTUnwrap(capture.path).wrappedValue = Array(repeating: .detail(secret: secret), count: depth)
            try await awaitSemanticBoundary("native-reveal-\(depth)", core: core) {
                snapshot()?.viewName == (depth == 0 ? "Root" : "Detail") && snapshot()?.viewID != ids.last
            }
            try await awaitSemanticBoundary("native-reader-depth-\(depth)", core: core) {
                capture.proof(viewID: snapshot()?.viewID, depth: depth, fixture: fixture, rows: rows) != nil
            }
            capture.proofs.append(try XCTUnwrap(capture.proof(viewID: snapshot()?.viewID, depth: depth, fixture: fixture, rows: rows)))
            let id = try XCTUnwrap(snapshot()?.viewID)
            XCTAssertFalse(ids.contains(id))
            ids.append(id)
        }
        XCTAssertEqual(driver.child.states.last, 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(rows.views), as: UTF8.self).contains(secret))
        XCTAssertTrue(fixture.window.windowScene === fixture.scene)
        XCTAssertTrue(capture.observer?.window === fixture.window)
        phase = "manual-owner"
        feature.monitor.startView(
            key: "native-manual-override",
            name: "Manual Override",
            attributes: [:],
            sceneIdentifier: fixture.identifier
        )
        try await awaitSemanticBoundary("native-manual-owner", core: core) {
            snapshot()?.viewName == "Manual Override"
        }
        let manualID = try XCTUnwrap(snapshot()?.viewID)
        feature.monitor.addAction(
            type: .custom,
            name: "native-manual-action",
            attributes: [:],
            explicitTarget: .scene(fixture.identifier)
        )
        try await awaitSemanticBoundary("native-manual-action", core: core) {
            rows.actions.contains { $0.action.target?.name == "native-manual-action" }
        }
        XCTAssertEqual(rows.actions.first { $0.action.target?.name == "native-manual-action" }?.view.id, manualID)
        feature.monitor.stopView(
            key: "native-manual-override",
            attributes: [:],
            sceneIdentifier: fixture.identifier
        )
        try await awaitSemanticBoundary("native-manual-reveal", core: core) {
            snapshot()?.viewName == "Root"
        }
        let revealed = try XCTUnwrap(snapshot()?.viewID)
        XCTAssertFalse(ids.contains(revealed))
        ids.append(revealed)
        phase = "container-removal"
        let finalID = try XCTUnwrap(ids.last)
        driver.visible = false
        try await awaitSemanticBoundary("native-container-removal", core: core) {
            rows.views.contains { $0.view.id == finalID && $0.view.isActive == false }
        }
        phase = "initially-restored-equal-routes"
        let restored = NativeHostDriver(core: core)
        restored.path = [.detail(secret: secret), .detail(secret: secret)]
        let restoredCapture = NativeHostCapture()
        restoredCapture.observeBoundaries()
        _ = fixture.install(NativeHostRoot(driver: restored, capture: restoredCapture))
        try await awaitSemanticBoundary("native-restored-depth-two", core: core) {
            snapshot()?.viewName == "Detail" && snapshot()?.viewID != finalID
                && restoredCapture.proof(viewID: snapshot()?.viewID, depth: 2, fixture: fixture, rows: rows) != nil
        }
        let restoredID = try XCTUnwrap(snapshot()?.viewID)
        restoredCapture.proofs.append(try XCTUnwrap(restoredCapture.proof(viewID: restoredID, depth: 2, fixture: fixture, rows: rows)))
        try XCTUnwrap(restoredCapture.path).wrappedValue = [.detail(secret: secret)]
        try await awaitSemanticBoundary("native-restored-retained-depth-one", core: core) {
            snapshot()?.viewName == "Detail" && snapshot()?.viewID != restoredID
                && restoredCapture.proof(viewID: snapshot()?.viewID, depth: 1, fixture: fixture, rows: rows) != nil
        }
        restoredCapture.proofs.append(try XCTUnwrap(restoredCapture.proof(viewID: snapshot()?.viewID, depth: 1, fixture: fixture, rows: rows)))
        XCTAssertEqual(snapshot()?.sessionID, session)
        retainNativeHostEvidence(
            phase: "restored-and-retained-equal-routes",
            completed: true,
            fixture: fixture,
            rows: rows,
            driver: restored,
            capture: restoredCapture,
            ids: [restoredID, try XCTUnwrap(snapshot()?.viewID)]
        )
        completed = true
    }

    func testNativeNavigationStack_whenAdmissionRetires_itRejectsStaleCallbacksAndPreservesUnusedTracking() async throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Native semantic navigation requires iOS 27")
        }
        let fixture = try SemanticHostWindow()
        defer { fixture.restore() }
        for mode in ["off", "nop", "custom"] {
            let core: DatadogCoreProtocol
            let real: DatadogCore?
            let rows = SemanticHostRows()
            var feature: RUMFeature?
            let customSubscriber = mode == "custom" ? RUMCommandSubscriberMock() : nil
            defer { withExtendedLifetime(customSubscriber) {} }
            if mode == "nop" {
                real = nil
                core = NOPDatadogCore()
            } else {
                let instance = makeSemanticCore()
                real = instance
                core = instance
                feature = try makeSemanticFeature(in: instance, rows: rows, enabled: mode == "custom")
                if mode == "custom" {
                    let handler = try XCTUnwrap(feature?.instrumentation.viewsHandler as? RUMSceneViewsHandler)
                    handler.subscriber = customSubscriber
                    XCTAssertTrue(handler.subscriber === customSubscriber)
                }
            }
            defer { real?.stop() }
            let driver = NativeHostDriver(core: core)
            driver.trackLegacyContent = mode == "off"
            let capture = NativeHostCapture()
            _ = fixture.install(NativeHostRoot(driver: driver, capture: capture))
            try await awaitSemanticBoundary("native-unused-\(mode)", core: real) {
                capture.updates > 0 && driver.child.states == [0] && capture.admission == nil
            }
            XCTAssertNil(capture.state?.source)
            XCTAssertNil(capture.observer)
            if mode == "off" {
                try await awaitSemanticBoundary("native-unused-legacy", core: real) {
                    feature?.monitor.activeView.name == "Native Legacy Content"
                        && rows.views.contains { $0.view.name == "Native Legacy Content" && $0.view.isActive == true }
                }
            }
            try XCTUnwrap(driver.child.update)()
            try await awaitSemanticBoundary("native-unused-content-\(mode)", core: real) {
                driver.child.states.last == 1
            }
            retainNativeHostEvidence(
                phase: "unused-\(mode)",
                completed: true,
                fixture: fixture,
                rows: rows,
                driver: driver,
                capture: capture,
                ids: []
            )
        }

        let original = makeSemanticCore()
        defer { original.stop() }
        let previousHook = RUMNativeNavigationTesting.onBoundary
        defer { RUMNativeNavigationTesting.onBoundary = previousHook }
        let originalRows = SemanticHostRows()
        let originalFeature = try makeSemanticFeature(in: original, rows: originalRows)
        let driver = NativeHostDriver(core: original)
        let capture = NativeHostCapture()
        capture.observeBoundaries()
        _ = fixture.install(NativeHostRoot(driver: driver, capture: capture))
        try await awaitSemanticBoundary("native-original", core: original) {
            originalFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Root"
        }
        try verifyNativeReentrancy(binding: XCTUnwrap(capture.admission).binding)
        let state = try XCTUnwrap(capture.state)
        let admission = try XCTUnwrap(capture.admission)
        let originalPath = try XCTUnwrap(capture.path)
        original.stop()
        XCTAssertFalse(admission.isValid)
        originalPath.wrappedValue = [.detail(secret: "accepted-after-sdk-stop")]
        XCTAssertEqual(driver.path, [.detail(secret: "accepted-after-sdk-stop")])
        XCTAssertNil(state.source(for: admission))
        driver.core = NOPDatadogCore()
        let directory = temporaryUniqueCoreDirectory()
        try directory.create()
        defer { try? directory.delete() }
        let peer = makeSemanticCore(directory: directory)
        defer { peer.stop() }
        let peerRows = SemanticHostRows()
        let peerFeature = try makeSemanticFeature(in: peer, rows: peerRows)
        let peerDriver = NativeHostDriver(core: peer)
        let peerCapture = NativeHostCapture()
        _ = fixture.install(NativeHostRoot(driver: peerDriver, capture: peerCapture))
        try await awaitSemanticBoundary("native-peer", core: peer) {
            peerFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewName == "Root"
        }
        let peerID = try XCTUnwrap(peerFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID)
        let drained = expectation(description: "Original native callback drained")
        DispatchQueue.main.async {
            state.reconcile(path: [.detail(secret: "stale")], metadata: .automatic, admission: admission)
            state.reconcile(attachment: .detached, admission: admission)
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 10)
        peer.flush()
        XCTAssertEqual(peerFeature.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID, peerID)
        XCTAssertFalse(peerRows.views.contains { $0.view.name == "Detail" })
        retainNativeHostEvidence(
            phase: "peer-after-original-retirement",
            completed: true,
            fixture: fixture,
            rows: peerRows,
            driver: peerDriver,
            capture: peerCapture,
            ids: [peerID]
        )
    }
}

private enum NativeHostRoute: Hashable {
    case detail(secret: String)
}

@available(iOS 27.0, *)
@MainActor
private final class NativeHostDriver: ObservableObject {
    @Published var core: DatadogCoreProtocol
    @Published var path: [NativeHostRoute] = []
    @Published var visible = true
    var acceptsProposals = true
    var trackLegacyContent = false
    var forwardedTransactions: [Bool] = []
    var materializedDepths: [Int] = []
    let child = OrdinarySwiftUIViewDriver()

    init(core: DatadogCoreProtocol) {
        self.core = core
    }
}

@available(iOS 27.0, *)
@MainActor
private final class NativeHostCapture {
    weak var state: RUMNativeNavigationState<NativeHostRoute>?
    weak var admission: RUMSwiftUIViewCallbackAdmission?
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    var path: Binding<[NativeHostRoute]>?
    var updates = 0
    var boundaries: [NativeBoundaryObservation] = []
    var proofs: [[String: Any]] = []
    var retainedOutgoingStates: [RUMViewTrackingState] = []
    var boundaryHookEvents = 0
    var unmatchedSourceCallbacks = 0
    var lastProofDiagnostic: [String: Any] = [:]

    func observeBoundaries() {
        RUMNativeNavigationTesting.onBoundary = { [weak self] source, observer, state, admission, configuration in
            guard let self else {
                return
            }
            self.boundaryHookEvents += 1
            guard let source else {
                return
            }
            if source !== self.state?.source {
                self.unmatchedSourceCallbacks += 1
            }
            // Retain weak observations before the offered source is known.
            // The proof still requires the exact current source.
            if let existing = self.boundaries.first(where: { $0.state === state && $0.observer === observer }) {
                existing.originConfiguration = configuration
            } else {
                self.boundaries.append(NativeBoundaryObservation(
                    source: source,
                    observer: observer,
                    state: state,
                    admission: admission,
                    originConfiguration: configuration
                ))
            }
        }
    }

    func proof(
        viewID: String?,
        depth: Int,
        fixture: SemanticHostWindow,
        rows: SemanticHostRows
    ) -> [String: Any]? {
        var predicates: [String: Bool] = [:]
        lastProofDiagnostic = [
            "requested_view_id": viewID ?? "", "requested_depth": depth,
            "boundary_hook_events": boundaryHookEvents,
            "unmatched_source_callbacks": unmatchedSourceCallbacks,
            "observed_boundary_count": boundaries.count,
            "absent_predicates": "not evaluated because an earlier guard failed"
        ]
        defer { lastProofDiagnostic["top_level_predicates"] = predicates }
        func checked(_ name: String, _ value: Bool) -> Bool {
            predicates[name] = value
            return value
        }
        func failed(_ name: String) -> [String: Any]? {
            predicates[name] = false
            lastProofDiagnostic["failed_predicate"] = name
            return nil
        }
        guard let viewID else {
            return failed("view_id_present")
        }
        predicates["view_id_present"] = true
        guard let current = admission else {
            return failed("admission_present")
        }
        predicates["admission_present"] = true
        guard checked("admission_valid", current.isValid) else {
            return failed("admission_valid")
        }
        guard let source = state?.source else {
            return failed("native_source_present")
        }
        predicates["native_source_present"] = true
        guard let row = rows.views.last(where: { $0.view.id == viewID && $0.view.isActive == true }) else {
            return failed("active_mapper_row_present")
        }
        predicates["active_mapper_row_present"] = true
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(row)
            predicates["mapper_encoding_succeeded"] = true
        } catch {
            lastProofDiagnostic["encoding_error_type"] = String(reflecting: type(of: error))
            return failed("mapper_encoding_succeeded")
        }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: encoded)
            predicates["mapper_decoding_succeeded"] = true
        } catch {
            lastProofDiagnostic["decoding_error_type"] = String(reflecting: type(of: error))
            return failed("mapper_decoding_succeeded")
        }
        let claim = Self.values(named: "native_test_claim", in: json).first
        predicates["mapper_claim_present"] = claim != nil
        guard let token = claim as? String else {
            return failed("mapper_claim_is_string")
        }
        predicates["mapper_claim_is_string"] = true
        guard let eligible = current.foundation?.makeEligibilityCheck() else {
            return failed("eligibility_available")
        }
        predicates["eligibility_available"] = true
        var boundaryPredicates: [[String: Bool]] = []
        let matching = boundaries.filter { boundary in
            var checks: [String: Bool] = [:]
            defer { boundaryPredicates.append(checks) }
            func checked(_ name: String, _ value: Bool) -> Bool {
                checks[name] = value
                return value
            }
            guard let state = boundary.state else {
                checks["state_present"] = false
                return false
            }
            checks["state_present"] = true
            guard let admission = boundary.admission else {
                checks["admission_present"] = false
                return false
            }
            checks["admission_present"] = true
            guard let observer = boundary.observer else {
                checks["reader_present"] = false
                return false
            }
            checks["reader_present"] = true
            guard checked("admission_valid", admission.isValid),
                  checked("source_matches", boundary.source === source),
                  checked("state_admission_matches", state.admission?.matches(admission) == true),
                  checked("epoch_matches", admission.binding.epoch == current.binding.epoch),
                  checked("lifetime_matches", admission.binding.lifetime === current.binding.lifetime),
                  checked("window_matches", observer.window === fixture.window),
                  checked("reader_scene_matches", observer.currentSceneIdentifier == fixture.identifier),
                  checked("state_scene_matches", state.sceneIdentifier == fixture.identifier),
                  checked("active_occurrence", state.activeLifecycleGeneration != nil),
                  checked("origin_depth_matches", boundary.originConfiguration?.descriptor.attributes["native_test_depth"] as? Int == depth)
            else {
                return false
            }
            guard let configuration = state.configuration else {
                checks["configuration_present"] = false
                return false
            }
            checks["configuration_present"] = true
            guard checked("current_destination", configuration.isCurrentDestination),
                  checked("claim_matches", configuration.descriptor.attributes["native_test_claim"] as? String == token),
                  checked("depth_matches", configuration.descriptor.attributes["native_test_depth"] as? Int == depth)
            else {
                return false
            }
            guard let controller = observer.nearestViewController else {
                checks["controller_present"] = false
                return false
            }
            checks["controller_present"] = true
            return checked("controller_ineligible", !eligible(controller))
        }
        lastProofDiagnostic["boundary_predicates"] = boundaryPredicates
        lastProofDiagnostic["matching_count"] = matching.count
        guard checked("exactly_one_match", matching.count == 1), let selected = matching.first else {
            return failed("exactly_one_match")
        }
        guard let reader = selected.observer else {
            return failed("selected_reader_present")
        }
        predicates["selected_reader_present"] = true
        guard let boundary = selected.state else {
            return failed("selected_state_present")
        }
        predicates["selected_state_present"] = true
        lastProofDiagnostic["failed_predicate"] = "none"
        return [
            "view_id": viewID, "depth": depth, "claim": token,
            "tracking_state": String(describing: ObjectIdentifier(boundary)),
            "reader": String(describing: ObjectIdentifier(reader)),
            "source": String(describing: ObjectIdentifier(source)),
            "scene": fixture.identifier.rawValue,
            "window": String(describing: ObjectIdentifier(fixture.window)),
            "native_controller_ineligible_for_automatic_tracking": true,
            "original_admission_valid": true,
            "retained_outgoing_states": retainedOutgoingStates.map { state in
                [
                    "state": String(describing: ObjectIdentifier(state)),
                    "admission_valid": state.admission?.isValid == true,
                    "has_active_occurrence": state.activeLifecycleGeneration != nil,
                    "selected_current_boundary": state === boundary
                ] as [String: Any]
            }
        ]
    }

    private static func values(named key: String, in value: Any) -> [Any] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { name, child in
                name == key ? [child] : values(named: key, in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap { values(named: key, in: $0) }
        }
        return []
    }
}

@available(iOS 27.0, *)
@MainActor
private final class NativeBoundaryObservation {
    weak var source: RUMSwiftUINavigationOccurrenceSource?
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    weak var state: RUMViewTrackingState?
    weak var admission: RUMSwiftUIViewCallbackAdmission?
    var originConfiguration: RUMViewTrackingState.Configuration?

    init(
        source: RUMSwiftUINavigationOccurrenceSource,
        observer: RUMSceneIdentifierReader.ObserverView,
        state: RUMViewTrackingState,
        admission: RUMSwiftUIViewCallbackAdmission,
        originConfiguration: RUMViewTrackingState.Configuration?
    ) {
        self.source = source
        self.observer = observer
        self.state = state
        self.admission = admission
        self.originConfiguration = originConfiguration
    }
}

@available(iOS 27.0, *)
@MainActor
private struct NativeHostRoot: View {
    @ObservedObject var driver: NativeHostDriver
    let capture: NativeHostCapture

    @ViewBuilder private var root: some View {
        if driver.trackLegacyContent {
            OrdinarySwiftUIViewChild(driver: driver.child)
                .trackRUMView(name: "Native Legacy Content", in: driver.core)
        } else {
            OrdinarySwiftUIViewChild(driver: driver.child)
        }
    }

    @ViewBuilder var body: some View {
        if driver.visible {
            RUMNavigationStack(
                path: Binding(get: { driver.path }, set: { proposal, transaction in
                    driver.forwardedTransactions.append(transaction.disablesAnimations)
                    if driver.acceptsProposals {
                        driver.path = proposal
                    }
                }),
                in: driver.core,
                root: { root },
                destination: { _ in
                    Text("Native detail")
                        .onAppear { driver.materializedDepths.append(driver.path.count) }
                }
            )
            .withTestingOnNativeUpdate { state, admission, observer, path in
                capture.state = state
                capture.admission = admission
                capture.path = path
                capture.updates += 1
                if let observer {
                    capture.observer = observer
                }
            }
        }
    }
}

@MainActor
private extension SwiftUINavigationOwnershipTests {
    @available(iOS 27.0, *)
    func verifyNativeReentrancy(binding: RUMSwiftUIViewFoundationBinding) throws {
        let state = RUMNativeNavigationState<NativeReentryRoute>()
        let admission = try XCTUnwrap(state.configure(binding: binding))
        defer { _ = state.configure(binding: nil) }
        let initial = NativeReentryRoute(1)
        let outer = NativeReentryRoute(2)
        let newest = NativeReentryRoute(3)
        state.reconcile(path: [initial], metadata: .automatic, admission: admission)
        initial.onEquality = {
            state.reconcile(path: [newest, newest], metadata: .automatic, admission: admission)
        }
        state.reconcile(path: [outer], metadata: .automatic, admission: admission)
        XCTAssertEqual(state.acceptedDepth, 2)

        let metadata = RUMNavigationMetadata.automatic.overriding(outer, name: "Outer")
        outer.onHash = {
            state.reconcile(path: [newest, newest, newest], metadata: .automatic, admission: admission)
        }
        state.reconcile(path: [outer], metadata: metadata, admission: admission)
        XCTAssertEqual(state.acceptedDepth, 3)

        state.reconcile(path: [initial], metadata: .automatic, admission: admission)
        let claim = state.makeClaim(for: initial)
        initial.onEquality = {
            state.reconcile(path: [newest, newest], metadata: .automatic, admission: admission)
        }
        XCTAssertNil(state.configuration(for: outer, retaining: claim, admission: admission))
        XCTAssertEqual(state.acceptedDepth, 2)

        state.reconcile(
            acceptedPath: {
                state.reconcile(path: [newest, newest, newest], metadata: .automatic, admission: admission)
                return [outer]
            },
            metadata: .automatic,
            admission: admission
        )
        XCTAssertEqual(state.acceptedDepth, 3)

        newest.onEquality = { _ = state.configure(binding: nil) }
        state.reconcile(path: [outer, outer, outer], metadata: .automatic, admission: admission)
        XCTAssertNil(state.admission)
        XCTAssertNil(state.source)
        XCTAssertEqual(state.acceptedDepth, 3)
    }

    @available(iOS 27.0, *)
    func retainNativeHostEvidence(
        phase: String,
        completed: Bool,
        fixture: SemanticHostWindow,
        rows: SemanticHostRows,
        driver: NativeHostDriver,
        capture: NativeHostCapture,
        ids: [String]
    ) {
        do {
            let views = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows.views))
            let actions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows.actions))
            let evidence: [String: Any] = [
                "schema_version": 1, "family": "native-navigation-materialization",
                "phase": phase, "completed": completed,
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "scene_identifier": fixture.identifier.rawValue,
                "owned_window": String(describing: ObjectIdentifier(fixture.window)),
                "reader_window": capture.observer?.window.map { String(describing: ObjectIdentifier($0)) } ?? "",
                "reader_scene": capture.observer?.currentSceneIdentifier?.rawValue ?? "",
                "path_depth": driver.path.count, "materialized_depths": driver.materializedDepths,
                "customer_states": driver.child.states, "view_ids": ids,
                "admission_valid": capture.admission?.isValid == true,
                "has_native_source": capture.state?.source != nil,
                "actual_boundary_proofs": capture.proofs,
                "boundary_hook_events": capture.boundaryHookEvents,
                "unmatched_source_callbacks": capture.unmatchedSourceCallbacks,
                "last_boundary_proof_diagnostic": capture.lastProofDiagnostic,
                "views": views, "actions": actions,
                "scope": "Rendered native typed-array component; no actual interactive OS transition or final-release claim"
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: evidence),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "native-navigation-materialization-" + phase
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not retain native navigation evidence")
        }
    }
}

/// Customer equality/hash callbacks deliberately reenter the native coordinator.
private final class NativeReentryRoute: Hashable {
    let value: Int
    var onEquality: (@MainActor () -> Void)?
    var onHash: (@MainActor () -> Void)?

    init(_ value: Int) {
        self.value = value
    }

    static func == (lhs: NativeReentryRoute, rhs: NativeReentryRoute) -> Bool {
        let callback = lhs.onEquality ?? rhs.onEquality
        lhs.onEquality = nil
        rhs.onEquality = nil
        if let callback {
            MainActor.assumeIsolated { callback() }
        }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        let callback = onHash
        onHash = nil
        if let callback {
            MainActor.assumeIsolated { callback() }
        }
        hasher.combine(value)
    }
}

#endif
