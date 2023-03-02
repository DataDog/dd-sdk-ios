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
    /*
          R
         / \
        I1  V1
    */
    func testFlattenNodes_withInvisibleNode() {
        // Given
        let smallFrame: CGRect = .mockRandom(minWidth: 1, maxWidth: 10, minHeight: 1, maxHeight: 10)
        let bigFrame: CGRect = .mockRandom(minWidth: 11, maxWidth: 100, minHeight: 11, maxHeight: 100)
        let invisibleNode = Node.mockWith(
            viewAttributes: .mock(fixture: .invisible)
        )
        let visibleNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: smallFrame)
        )
        let rootNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: bigFrame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(nodes: [rootNode, invisibleNode, visibleNode])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [rootNode, visibleNode])
    }

    /*
        V
        |
        V1
    */
    func testFlattenNodes_withVisibleNodeThatCoversAnotherNode() {
        // Given
        let frame = CGRect.mockRandom(minWidth: 1, minHeight: 1)
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode = Node.mockWith(
            viewAttributes: .mockRandom(),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(nodes: [coveredNode, coveringNode])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes.count, 1)
        DDAssertReflectionEqual(flattenedNodes, [coveringNode])
    }

    /*
          R
         / \
        I1  V2
       /
      V1
    */
    func testFlattenNodes_withMixedVisibleAndInvisibleNodes() {
        // Given
        let frame1: CGRect = .mockRandom(minWidth: 1, maxWidth: 10, minHeight: 1, maxHeight: 10)
        let frame2: CGRect = .mockRandom(minWidth: 11, maxWidth: 100, minHeight: 11, maxHeight: 100)
        let rootFrame: CGRect = .mockRandom(minWidth: 101, maxWidth: 1_000, minHeight: 101, maxHeight: 1_000)
        let visibleNode1 = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: frame1)
        )
        let invisibleNode1 = Node.mockWith(viewAttributes: .mock(fixture: .invisible))
        let visibleNode2 = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: frame2)
        )
        let rootNode = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: rootFrame)
        )

        let snapshot = ViewTreeSnapshot.mockWith(nodes: [rootNode, invisibleNode1, visibleNode1, visibleNode2])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [rootNode, visibleNode1, visibleNode2])
    }

    /*
          R
        /   \
      CN1  CN2
       |    |
       CN   CN
    */
    func testFlattenNodes_withMultipleVisibleNodesThatAreCoveredByAnotherNode() {
        // Given
        // set rects
        let frame = CGRect.mockRandom()
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode1 = Node.mockWith(
            viewAttributes: .mockRandom(),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let coveredNode2 = Node.mockWith(
            viewAttributes: .mockRandom(),
            semantics: SpecificElement.mock(wireframeRect: frame)
        )
        let rootNode = Node.mockAny()
        let snapshot = ViewTreeSnapshot.mockWith(nodes: [rootNode, coveredNode1, coveringNode, coveredNode2, coveringNode])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [coveringNode])
    }

    /*
          R
         / \
        V1  V2
    */
    func testFlattenNodes_withNodesWithSameFrameAndDifferentAppearances() {
        // Given
        let smallFrame: CGRect = .mockRandom(minWidth: 1, maxWidth: 10, minHeight: 1, maxHeight: 10)
        let bigFrame: CGRect = .mockRandom(minWidth: 11, maxWidth: 100, minHeight: 11, maxHeight: 100)
        let visibleNode1 = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: smallFrame)
        )
        let visibleNode2 = Node.mockWith(
            viewAttributes: .mock(fixture: .visible()),
            semantics: SpecificElement.mock(wireframeRect: bigFrame)
        )
        let rootNode = Node.mockAny()
        let snapshot = ViewTreeSnapshot.mockWith(nodes: [rootNode, visibleNode1, visibleNode2])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [visibleNode1, visibleNode2])
   }
}
