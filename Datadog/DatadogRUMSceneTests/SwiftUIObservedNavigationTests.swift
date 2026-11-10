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
                if path == "off" {
                    try await awaitLegacySemanticView(
                        "observed-legacy-content-off",
                        core: real,
                        feature: feature,
                        rows: rows,
                        viewName: "Observed Legacy Content"
                    )
                } else if path == "content-only" {
                    try await awaitSemanticBoundary("observed-legacy-content-content-only", core: real) {
                        let activeID = feature?.monitor.rumContextSnapshot(for: .scene(fixture.identifier))?.viewID
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

#endif
