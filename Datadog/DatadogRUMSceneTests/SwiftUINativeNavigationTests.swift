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

#if os(iOS) && canImport(SwiftUI) && compiler(>=6.4) && canImport(Observation)
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
                try await awaitLegacySemanticView(
                    "native-unused-legacy",
                    core: real,
                    feature: feature,
                    rows: rows,
                    viewName: "Native Legacy Content"
                )
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
