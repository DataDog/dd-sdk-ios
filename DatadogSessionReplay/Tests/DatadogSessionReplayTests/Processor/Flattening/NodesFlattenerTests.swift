/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

class NodesFlattenerTests: XCTestCase {
    func testFlattenNodes_withInvisibleNode() {
        // Given
        let invisibleNode = Node.mockWith(semantics: InvisibleElement.constant)
        let visibleNode = Node.mockWith(semantics: SpecificElement.mockAny())
        let rootNode = Node.mockWith(children: [invisibleNode, visibleNode])
        let snapshot = ViewTreeSnapshot.mockWith(root: rootNode)
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        XCTAssertEqual(flattenedNodes, [visibleNode])
    }

    func testFlattenNodes_withVisibleNodeThatCoversAnotherNode() {
        // Given
        let frame = CGRect.mockAny()
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
            semantics: SpecificElement.mock(wireframeRect: frame),
            children: [coveringNode]
        )
        let snapshot = ViewTreeSnapshot.mockWith(root: coveredNode)
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        XCTAssertEqual(flattenedNodes.count, 2)
        XCTAssertEqual(flattenedNodes, [coveredNode, coveringNode])
    }

    func testFlattenNodes_withMixedVisibleAndInvisibleNodes() {
        // Given
        let visibleNode2 = Node.mockWith(semantics: SpecificElement.mockAny())
        let invisibleNode1 = Node.mockWith(semantics: InvisibleElement.constant, children: [visibleNode2])
        let visibleNode1 = Node.mockWith(semantics: SpecificElement.mockAny())
        let rootNode = Node.mockWith(children: [invisibleNode1, visibleNode1])

        let snapshot = ViewTreeSnapshot.mockWith(root: rootNode)
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        XCTAssertEqual(flattenedNodes[0], visibleNode1)
    }

    func testFlattenNodes_withMultipleVisibleNodesThatAreCoveredByAnotherNode() {
        // Given
        let frame = CGRect.mockAny()
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode1 = Node.mockWith(
            viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode2 = Node.mockWith(
            viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let rootNode = Node.mockWith(
            children: [coveringNode, coveredNode1, coveredNode2]
        )
        let snapshot = ViewTreeSnapshot.mockWith(root: rootNode)
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        XCTAssertEqual(flattenedNodes.count, 3)
        XCTAssertEqual(flattenedNodes, [coveringNode, coveredNode1, coveredNode2])
    }

    func testFlattenNodes_withNodesWithSameFrameAndDifferentAppearances() {
       // Given
       let frame = CGRect.mockAny()
       let visibleNode = Node.mockWith(
           viewAttributes: .mock(fixture: .visibleWithSomeAppearance),
           semantics: SpecificElement.mock(wireframeRect: frame)
       )
       let invisibleNode = Node.mockWith(
           viewAttributes: .mock(fixture: .visibleWithNoAppearance),
           semantics: SpecificElement.mock(wireframeRect: frame)
       )
       let rootNode = Node.mockWith(children: [invisibleNode, visibleNode])
       let snapshot = ViewTreeSnapshot.mockWith(root: rootNode)
       let flattener = NodesFlattener()

       // When
       let flattenedNodes = flattener.flattenNodes(in: snapshot)

       // Then
       XCTAssertEqual(flattenedNodes, [invisibleNode, visibleNode])
   }
}
