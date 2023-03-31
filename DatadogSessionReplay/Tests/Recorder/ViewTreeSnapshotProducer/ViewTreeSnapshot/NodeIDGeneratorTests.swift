/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogSessionReplay
@testable import TestUtilities

class NodeIDGeneratorTests: XCTestCase {
    private let n: Int = .mockRandom(min: 1, max: 100)

    func testAfterIDisRetrievedFirstTime_itAlwaysReturnsTheSameIDForUIViewInstance() {
        // Given
        let view1: UIView = .mockRandom()
        let view2: UIView = .mockRandom()

        // When
        let generator = NodeIDGenerator()
        let id = generator.nodeID(for: view1)
        let ids = generator.nodeIDs(n, for: view2)

        // Then
        XCTAssertEqual(id, generator.nodeID(for: view1))
        XCTAssertEqual(ids, generator.nodeIDs(n, for: view2))
    }

    func testAllIDsAreUnique() {
        // Given
        let viewsWithID: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }
        let viewsWithIDs: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }

        // When
        let generator = NodeIDGenerator(currentID: .mockRandom())
        let ids = viewsWithID.map { generator.nodeID(for: $0) }
        let idNs = viewsWithIDs.map { generator.nodeIDs(n, for: $0) }

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
        XCTAssertEqual(generator.nodeID(for: .mockRandom()), currentID)
        XCTAssertEqual(generator.nodeID(for: .mockRandom()), maxID)
        XCTAssertEqual(generator.nodeID(for: .mockRandom()), 0)
    }

    func testGivenIDsRetrievedFirstTime_whenQueryingForDifferentSize_itReturnsDistinctIDs() {
        // Given
        let view: UIView = .mockRandom()
        let generator = NodeIDGenerator()
        let ids1 = generator.nodeIDs(n, for: view)

        // When
        let ids2 = generator.nodeIDs(.mockRandom(min: 1, max: 100, otherThan: [n]), for: view)

        // Then
        XCTAssertEqual(Set(ids1).intersection(Set(ids2)), [])
    }
}
