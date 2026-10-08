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
#endif
