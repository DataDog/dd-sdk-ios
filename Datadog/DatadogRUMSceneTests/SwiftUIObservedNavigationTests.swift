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
