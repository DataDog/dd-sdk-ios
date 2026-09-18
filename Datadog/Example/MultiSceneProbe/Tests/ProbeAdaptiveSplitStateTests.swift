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

    func testResizeRequiresAcceptedSelectionAndConsumesFiniteNativeSequence() {
        let router = ProbeAdaptiveSplitState()
        XCTAssertNil(consume(router, sequence: 10, width: 900, height: 675, sizeClass: "regular"))
        router.select(.detailOne)
        XCTAssertEqual(consume(router, sequence: 10, width: 900, height: 675, sizeClass: "regular"), 1)
        XCTAssertNil(consume(router, sequence: 10, width: 400, height: 700, sizeClass: "compact"))
        XCTAssertEqual(consume(router, sequence: 11, width: 400, height: 700, sizeClass: "compact"), 2)
        XCTAssertEqual(consume(router, sequence: 12, width: 900, height: 675, sizeClass: "regular"), 3)
        XCTAssertNil(consume(router, sequence: 13, width: 900, height: 675, sizeClass: "regular"))
    }

    func testResizeRejectsWrongSceneBackgroundAndStaleLiveGeometry() {
        for variation in ["scene", "background", "geometry", "route"] {
            let router = ProbeAdaptiveSplitState()
            router.select(.detailOne)
            XCTAssertNil(consume(
                router, sequence: 10, width: 900, height: 675, sizeClass: "regular",
                variation: variation
            ))
            XCTAssertEqual(consume(router, sequence: 11, width: 900, height: 675, sizeClass: "regular"), 1)
        }
    }

    private func consume(
        _ router: ProbeAdaptiveSplitState,
        sequence: UInt64,
        width: Double,
        height: Double,
        sizeClass: String,
        variation: String? = nil
    ) -> Int? {
        let geometry = ProbeGeometry(x: 0, y: 0, width: width, height: height)
        let signal = ProbeSignal(
            kind: .sceneGeometry,
            sequence: sequence,
            semanticContext: ProbeSemanticContext(
                logicalSceneID: "scene-A", nativeSceneID: variation == "scene" ? "other" : "native-A"
            ),
            activationState: variation == "background" ? "background" : "foreground-active",
            geometry: geometry,
            horizontalSizeClass: sizeClass,
            navigationPath: variation == "route" ? [] : ["detail-1"]
        )
        let live = ProbeScenePresentation(
            activationState: .foregroundActive,
            geometry: variation == "geometry" ? ProbeGeometry(x: 0, y: 0, width: 1, height: 1) : geometry,
            horizontalSizeClass: sizeClass,
            verticalSizeClass: "regular"
        )
        return router.consumeResize(signal, live: live, logicalSceneID: "scene-A", nativeSceneID: "native-A")
    }

}
