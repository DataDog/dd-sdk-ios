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
    func testAfterIDisRetrievedFirstTime_itAlwaysReturnsTheSameIDForUIViewInstance() {
        // Given
        let view1: UIView = .mockRandom()
        let view2: UIView = .mockRandom()

        // When
        let generator = NodeIDGenerator()
        let id = generator.nodeID(for: view1)
        let id2 = generator.nodeID2(for: view2)

        // Then
        XCTAssertEqual(id, generator.nodeID(for: view1))
        XCTAssertEqual(id2.0, generator.nodeID2(for: view2).0)
        XCTAssertEqual(id2.1, generator.nodeID2(for: view2).1)
    }

    func testAllIDsAreUnique() {
        // Given
        let viewsWithID: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }
        let viewsWithID2: [UIView] = (0..<100).map { _ in UIView(frame: .mockRandom()) }

        // When
        let generator = NodeIDGenerator(currentID: .mockRandom())
        let ids = viewsWithID.map { generator.nodeID(for: $0) }
        let id2s = viewsWithID2.map { generator.nodeID2(for: $0) }

        // Then
        let allIDs: Set<NodeID> = zip(ids, id2s).reduce(into: []) { result, ids in
            result.insert(ids.0)
            result.insert(ids.1.0)
            result.insert(ids.1.1)
        }
        XCTAssertEqual(allIDs.count, viewsWithID.count + viewsWithID2.count * 2)
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
}
