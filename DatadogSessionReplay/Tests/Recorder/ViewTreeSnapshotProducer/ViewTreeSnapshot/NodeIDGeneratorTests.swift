/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

class NodeIDGeneratorTests: XCTestCase {
    private let n: Int = .mockRandom(min: 1, max: 100)
    private let nodeRecorder = NodeRecorderMock()

    func testAfterIDisRetrievedFirstTime_itAlwaysReturnsTheSameIDForUIViewInstance() {
        // Given
        let view1: UIView = .mockRandom()
        let view2: UIView = .mockRandom()

        // When
        let generator = NodeIDGenerator()
        let id = generator.nodeID(view: view1, nodeRecorder: nodeRecorder)
        let ids = generator.nodeIDs(n, view: view2, nodeRecorder: nodeRecorder)

        // Then
        XCTAssertEqual(id, generator.nodeID(view: view1, nodeRecorder: nodeRecorder))
        XCTAssertEqual(ids, generator.nodeIDs(n, view: view2, nodeRecorder: nodeRecorder))
    }

    func testAllIDsAreUnique() {
        // Given
        let viewsWithID: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }
        let viewsWithIDs: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }

        // When
        let generator = NodeIDGenerator(currentID: .mockRandom())
        let ids = viewsWithID.map { generator.nodeID(view: $0, nodeRecorder: nodeRecorder) }
        let idNs = viewsWithIDs.map { generator.nodeIDs(n, view: $0, nodeRecorder: nodeRecorder) }

        // Then
        let singleIDs: Set<NodeID> = ids.reduce(into: []) { result, id in result.insert(id) }
        let mulitpleIDs: Set<[NodeID]> = idNs.reduce(into: []) { result, ids in result.insert(ids) }

        XCTAssertEqual(singleIDs.count, viewsWithID.count)
        XCTAssertEqual(mulitpleIDs.map({ Set($0) }).count, viewsWithIDs.count)
    }

    func testAfterReachingMaxID_itStartsAgainFromZero() {
        // Given
        let maxID: NodeID = .mockRandom(min: 1)
        let currentID: NodeID = maxID - 1

        // When
        let generator = NodeIDGenerator(currentID: currentID, maxID: maxID)

        // Then
        XCTAssertEqual(generator.nodeID(view: .mockRandom(), nodeRecorder: nodeRecorder), currentID)
        XCTAssertEqual(generator.nodeID(view: .mockRandom(), nodeRecorder: nodeRecorder), maxID)
        XCTAssertEqual(generator.nodeID(view: .mockRandom(), nodeRecorder: nodeRecorder), 0)
    }

    func testGivenIDsRetrievedFirstTime_whenQueryingForDifferentSize_itReturnsDistinctIDs() {
        // Given
        let view: UIView = .mockRandom()
        let generator = NodeIDGenerator()
        let ids1 = generator.nodeIDs(n, view: view, nodeRecorder: nodeRecorder)

        // When
        let ids2 = generator.nodeIDs(
            .mockRandom(min: 1, max: 100, otherThan: [n]),
            view: view,
            nodeRecorder: nodeRecorder
        )

        // Then
        XCTAssertEqual(Set(ids1).intersection(Set(ids2)), [])
    }

    func testIDisDifferentWhenRecorderChanges() {
        // Given
        let view: UIView = .mockRandom()
        let generator = NodeIDGenerator()
        let id = generator.nodeID(view: view, nodeRecorder: nodeRecorder)

        // When
        let newID = generator.nodeID(view: view, nodeRecorder: NodeRecorderMock())

        // Then
        XCTAssertNotEqual(id, newID)
    }

    func testIDchangesWhenViewChanges() {
        // Given
        let view1: UIView = .mockRandom()
        let view2: UIView = .mockRandom()
        let generator = NodeIDGenerator()
        let id = generator.nodeID(view: view1, nodeRecorder: nodeRecorder)

        // When
        let newID = generator.nodeID(view: view2, nodeRecorder: nodeRecorder)

        // Then
        XCTAssertNotEqual(id, newID)
    }
}
