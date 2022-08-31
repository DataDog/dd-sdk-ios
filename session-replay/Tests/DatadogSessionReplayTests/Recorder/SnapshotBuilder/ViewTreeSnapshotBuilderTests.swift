/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

private class NodeRecorderMock: NodeRecorder {
    var queriedViews: Set<UIView> = []
    var resultForView: (UIView) -> NodeSemantics?

    init(resultForView: @escaping (UIView) -> NodeSemantics?) {
        self.resultForView = resultForView
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        queriedViews.insert(view)
        return resultForView(view)
    }
}

class ViewTreeSnapshotBuilderTests: XCTestCase {
    // MARK: - Querying Node Recorders

    func testItQueriesAllNodeRecorders() {
        // Given
        let rootView = UIView(frame: .mockRandom())
        let childView = UIView(frame: .mockRandom())
        let grandchildView = UIView(frame: .mockRandom())
        childView.addSubview(grandchildView)
        rootView.addSubview(childView)

        // When
        let recorders: [NodeRecorderMock] = [
            NodeRecorderMock(resultForView: { _ in nil }),
            NodeRecorderMock(resultForView: { _ in nil }),
            NodeRecorderMock(resultForView: { _ in nil }),
        ]
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: recorders.map { $0.eraseToAnyNodeRecorder })
        _ = builder.createSnapshot(of: rootView)

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[1].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[2].queriedViews, [rootView, childView, grandchildView])
    }

    func testItQueriesNodeRecordersInOrderUntilOneFindsBestSemantics() {
        // Given
        let view = UIView(frame: .mockRandom())

        let unknownElement = UnknownElement.constant
        let ambiguousElement = AmbiguousElement(wireframesBuilder: NOPWireframesBuilderMock())
        let specificElement = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock())

        // When
        let recorders: [NodeRecorderMock] = [
            NodeRecorderMock(resultForView: { _ in unknownElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in specificElement }), // here we find best semantics...
            NodeRecorderMock(resultForView: { _ in specificElement }), // ... so this one should not be queried
        ]
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: recorders.map { $0.eraseToAnyNodeRecorder })
        _ = builder.createSnapshot(of: view)

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[1].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[2].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[3].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[4].queriedViews, [], "It should NOT be queried as 'specific' semantics is known")
    }

    // MARK: - Recording Nodes Recursively

    func testItQueriesViewTreeRecursively() {
        // Given
        let rootView = UIView(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let ambiguousChild = UIView(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let specificChild = UILabel(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let childOfAmbiguousElement = UIView(frame: .mockAny())
        let childOfSpecificElement = UIView(frame: .mockAny())

        ambiguousChild.addSubview(childOfAmbiguousElement)
        specificChild.addSubview(childOfSpecificElement)
        rootView.addSubview(ambiguousChild)
        rootView.addSubview(specificChild)

        let ambiguousElement = AmbiguousElement(wireframesBuilder: NOPWireframesBuilderMock())
        let specificElement = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock())

        let semanticsByView: [UIView: NodeSemantics] = [
            rootView: ambiguousElement,
            ambiguousChild: ambiguousElement,
            specificChild: specificElement,
            childOfAmbiguousElement: ambiguousElement,
            childOfSpecificElement: specificElement,
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [nodeRecorder.eraseToAnyNodeRecorder])
        let snapshot = builder.createSnapshot(of: rootView)

        // Then
        XCTAssertTrue(snapshot.root.semantics is AmbiguousElement)
        XCTAssertEqual(snapshot.root.children.count, 2)
        XCTAssertTrue(snapshot.root.children[0].semantics is AmbiguousElement)
        XCTAssertTrue(snapshot.root.children[1].semantics is SpecificElement)
        XCTAssertEqual(snapshot.root.children[0].children.count, 1, "It should resolve this sub-tree as parent node doesn't have 'specific' semantics")
        XCTAssertEqual(snapshot.root.children[1].children.count, 0, "It should NOT resolve this sub-tree as parent has 'specific' semantics")

        XCTAssertTrue(nodeRecorder.queriedViews.contains(rootView))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(ambiguousChild))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(specificChild))
        XCTAssertTrue(
            nodeRecorder.queriedViews.contains(childOfAmbiguousElement),
            "It should query `childViewOfBasicSemantis`, because the parent does not have 'specific' semantics"
        )
        XCTAssertFalse(
            nodeRecorder.queriedViews.contains(childOfSpecificElement),
            "It should NOT query `childViewOfMeaningfulSemantis`, because the parent has 'specific' semantics"
        )
    }
}
