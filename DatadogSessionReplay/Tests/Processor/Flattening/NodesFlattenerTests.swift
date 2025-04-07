/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

class NodesFlattenerTests: XCTestCase {
    /*
        V
        |
        V1
    */
    func testFlattenNodes_withNodeThatCoversAnotherNode() {
        // Given
        let viewportSize = CGSize.mockRandom(minWidth: 1, minHeight: 1)
        let frame = CGRect.mockRandom(
            maxX: viewportSize.width - 1,
            maxY: viewportSize.height - 1,
            minWidth: 1,
            minHeight: 1
        )
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let coveredNode = Node.mockWith(
            viewAttributes: .mockRandom(),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(
            viewportSize: viewportSize,
            nodes: [coveredNode, coveringNode]
        )
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [coveringNode])
    }

    /*
          R
        /   \
      CN1  CN2
       |    |
       CN   CN
    */
    func testFlattenNodes_withMultipleNodesThatAreCoveredByAnotherNode() {
        // Given
        let viewportSize = CGSize.mockRandom(minWidth: 1, minHeight: 1)
        let frame = CGRect.mockRandom(
            maxX: viewportSize.width - 1,
            maxY: viewportSize.height - 1,
            minWidth: 1,
            minHeight: 1
        )
        let coveringNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let coveredNode1 = Node.mockWith(
            viewAttributes: .mockRandom(),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let coveredNode2 = Node.mockWith(
            viewAttributes: .mockRandom(),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let rootNode = Node.mockWith(
            viewAttributes: .mockRandom(),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: frame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(
            viewportSize: viewportSize,
            nodes: [rootNode, coveredNode1, coveringNode, coveredNode2, coveringNode]
        )
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [coveringNode])
    }

    func testFlattenNodes_removesNodeWhenItsOutsideOfViewportSize() {
        // Given
        let viewportSize = CGSize.mockRandom()
        let outsideFrame = CGRect(origin: .init(x: viewportSize.width, y: viewportSize.height), size: .mockRandom())
        let outsideNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: outsideFrame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(viewportSize: viewportSize, nodes: [outsideNode])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [])
    }

    func testFlattenNodes_doesntRemovesNodeWhenItIntersectsWithViewportSize() {
        // Given
        let viewportSize = CGSize.mockRandom()
        let intersectingFrame = CGRect(origin: .init(x: viewportSize.width - 1, y: viewportSize.height - 1), size: .mockRandom())
        let intersectingNode = Node.mockWith(
            viewAttributes: .mock(fixture: .opaque),
            wireframesBuilder: ShapeWireframesBuilderMock(wireframeRect: intersectingFrame)
        )
        let snapshot = ViewTreeSnapshot.mockWith(viewportSize: viewportSize, nodes: [intersectingNode])
        let flattener = NodesFlattener()

        // When
        let flattenedNodes = flattener.flattenNodes(in: snapshot)

        // Then
        DDAssertReflectionEqual(flattenedNodes, [intersectingNode])
    }
}
#endif
