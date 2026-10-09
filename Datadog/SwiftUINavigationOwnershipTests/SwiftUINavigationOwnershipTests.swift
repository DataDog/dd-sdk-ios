/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
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
            _ = admission.withSession { session in
                _ = session.trackingState.reconcile(configuration: configuration(generation: 1),
                                                    attachment: .attached(scene), isAppeared: true)
                foundation.registerAuthority(observer: observer, trackingState: session.trackingState, admission: admission)
                // Actual deferred production storage retains this appeared state after holder retirement.
                arbiter.process(.disappear, state: session.trackingState) { _ in XCTFail("Completion was not released") }
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
        let expectedDelegateClass = try XCTUnwrap(NSClassFromString("SwiftUINavigationOwnershipHost.SwiftUINavigationOwnershipHostSceneDelegate"))
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
