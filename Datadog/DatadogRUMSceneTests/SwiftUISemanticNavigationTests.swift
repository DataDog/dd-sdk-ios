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
    @MainActor
    func makeSemanticCore(directory: CoreDirectory? = nil) -> DatadogCore {
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
    func makeSemanticFeature(
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
    func awaitSemanticBoundary(
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

    /// Reads the published legacy context on its SDK queue; Off has no scene snapshot store.
    @MainActor
    func awaitLegacySemanticView(
        _ boundary: String,
        core: DatadogCore?,
        feature: RUMFeature?,
        rows: SemanticHostRows,
        viewName: String
    ) async throws {
        let core = try XCTUnwrap(core)
        let feature = try XCTUnwrap(feature)
        guard !feature.monitor.isMultiSceneTrackingEnabled else {
            XCTFail("Legacy ownership check requires the Off path")
            throw OrdinarySwiftUIViewCaptureError.missingBoundary(boundary)
        }
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            core.flush()
            let current: (id: String?, name: String?) = await withCheckedContinuation { continuation in
                feature.monitor.featureScope.context { context in
                    let rum = context.additionalContext(ofType: RUMCoreContext.self)
                    continuation.resume(returning: (rum?.viewID, rum?.viewName))
                }
            }
            if let id = current.id, current.name == viewName,
               rows.views.contains(where: { $0.view.id == id && $0.view.name == viewName && $0.view.isActive == true }) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing legacy SwiftUI ownership boundary: \(boundary)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(boundary)
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
                try await awaitLegacySemanticView(
                    "legacy-content-tracking",
                    core: realCore,
                    feature: feature,
                    rows: rows,
                    viewName: "Legacy Content"
                )
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

final class SemanticHostRows: @unchecked Sendable {
    private let lock = NSLock()
    private var viewValues: [RUMViewEvent] = []
    private var actionValues: [RUMActionEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; viewValues.append(value) }
    func append(_ value: RUMActionEvent) { lock.lock(); defer { lock.unlock() }; actionValues.append(value) }
    var views: [RUMViewEvent] { lock.lock(); defer { lock.unlock() }; return viewValues }
    var actions: [RUMActionEvent] { lock.lock(); defer { lock.unlock() }; return actionValues }
}

@MainActor
final class SemanticHostWindow {
    let scene: UIWindowScene
    let window: UIWindow
    let identifier: RUMSceneIdentifier
    private let originalRoot: UIViewController
    private let originalHidden: Bool
    private let originalKey: UIWindow?

    init() throws {
        let expected = try XCTUnwrap(NSClassFromString("RUMSceneTestHost.RUMTestSceneDelegate"))
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
