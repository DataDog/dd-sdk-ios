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
