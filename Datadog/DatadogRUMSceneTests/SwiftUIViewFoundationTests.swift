/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
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
extension SwiftUINavigationOwnershipTests {










    @available(iOS 27.0, *)
    @MainActor
    private func makeStoppedSwiftUIOwnershipGraph() throws -> StoppedSwiftUIOwnershipGraph {
        // Release setup temporaries before the async test inspects the retained carriers.
        var core: DatadogCore? = makeHandoffCore()
        defer { core?.stop() }
        var feature: RUMFeature? = try makeOwnedSwiftUIFeature(in: try XCTUnwrap(core))
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
        let retained = StoppedSwiftUIOwnershipGraph(
            core: core,
            feature: feature,
            monitor: feature?.monitor,
            foundation: feature?.instrumentation.swiftUIViewFoundation,
            binding: binding,
            eligible: eligible,
            holder: holder,
            callback: callback,
            admission: admission,
            coordinator: coordinator,
            arbiter: arbiter,
            deliveries: { deliveries }
        )
        core?.flush()
        core?.stop()
        feature = nil
        core = nil
        return retained
    }




    @MainActor
    func drainOwnedMainDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }


    @MainActor
    func connectedSceneIdentifier(_ binding: RUMSwiftUIViewFoundationBinding) throws -> RUMSceneIdentifier {
        // Production scene proof is never replaced by a fabricated identifier.
        // A missing admitted host scene is not qualification of these controls.
        let expectedDelegateClass = try XCTUnwrap(NSClassFromString("RUMSceneTestHost.RUMTestSceneDelegate"))
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

    func configuration(generation: UInt64, name: String = "route") -> RUMViewTrackingState.Configuration {
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

@available(iOS 27.0, *)
@MainActor
private struct StoppedSwiftUIOwnershipGraph {
    weak var core: DatadogCore?
    weak var feature: RUMFeature?
    weak var monitor: Monitor?
    weak var foundation: RUMSwiftUIViewFoundation?
    let binding: RUMSwiftUIViewFoundationBinding
    let eligible: (UIViewController) -> Bool
    let holder: RUMSwiftUIViewTrackingEpoch
    let callback: RUMSwiftUIViewTrackingEpoch.Callback
    let admission: RUMSwiftUIViewCallbackAdmission
    let coordinator: RetainedCompletionCoordinator
    let arbiter: RUMSwiftUIInteractiveTransitionArbiter
    let deliveries: () -> Int
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
