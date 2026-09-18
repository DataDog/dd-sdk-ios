/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Combine
import XCTest

@MainActor
final class ProbeAdaptiveSplitStateTests: XCTestCase {
    func testPublishesAcceptedModelBeforeObserverAndImmediateWork() {
        let router = ProbeAdaptiveSplitState()
        var observed: [ProbeAdaptiveSplitState.Snapshot] = []
        let subscription = router.publisher.sink { snapshot in
            XCTAssertEqual(router.current, snapshot)
            observed.append(snapshot)
        }
        XCTAssertTrue(router.select(.detailOne))
        XCTAssertEqual(observed.last, router.current)
        XCTAssertEqual(router.current.destination.route, ["detail-1"])
        XCTAssertEqual(observed.map(\.generation), [0, 1])
        withExtendedLifetime(subscription) {}
    }

    func testEqualSelectionDoesNotCreateOccurrenceAndReturnIsFresh() {
        let router = ProbeAdaptiveSplitState()
        var generations: [UInt64] = []
        let subscription = router.publisher.sink { generations.append($0.generation) }
        XCTAssertTrue(router.select(.detailOne))
        XCTAssertFalse(router.select(.detailOne))
        XCTAssertTrue(router.select(.detailTwo))
        XCTAssertTrue(router.select(.detailOne))
        XCTAssertEqual(generations, [0, 1, 2, 3])
        withExtendedLifetime(subscription) {}
    }

    func testClearingSelectionAndIndependentSceneState() {
        let first = ProbeAdaptiveSplitState()
        let second = ProbeAdaptiveSplitState()
        XCTAssertTrue(first.select(.detailOne))
        XCTAssertEqual(second.current.destination, .empty)
        XCTAssertTrue(first.select(nil))
        XCTAssertEqual(first.current.destination.route, [])
        XCTAssertEqual(first.current.generation, 2)
        XCTAssertEqual(second.current.generation, 0)
    }
}
