/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class ViewTreeRecorderTests: XCTestCase {
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
        let recorder = ViewTreeRecorder(nodeRecorders: recorders)
        _ = recorder.recordNodes(for: rootView, in: .mockAny())

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
        let specificElement = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock(), recordSubtree: .mockRandom())

        // When
        let recorders: [NodeRecorderMock] = [
            NodeRecorderMock(resultForView: { _ in unknownElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in specificElement }), // here we find best semantics...
            NodeRecorderMock(resultForView: { _ in specificElement }), // ... so this one should not be queried
        ]
        let recorder = ViewTreeRecorder(nodeRecorders: recorders)
        _ = recorder.recordNodes(for: view, in: .mockAny())

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[1].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[2].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[3].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[4].queriedViews, [], "It should NOT be queried as 'specific' semantics is known")
    }

    // MARK: - Recording Nodes Recursively

    func testItQueriesViewTreeRecursivelyAndReturnsNodesInDFSOrder() {
        struct MockSemantics: NodeSemantics {
            static var importance: Int = .mockAny()
            var recordSubtree: Bool
            let wireframesBuilder: NodeWireframesBuilder? = nil
            let debugName: String
        }

        // Given
        let rootView = UIView(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let ambiguousChild = UIView(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let specificChild1 = UILabel(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let specificChild2 = UILabel(frame: .mockRandom(minWidth: 1, minHeight: 1))
        let childOfAmbiguousElement = UIView(frame: .mockAny())
        let childOfSpecificElement1 = UIView(frame: .mockAny())
        let childOfSpecificElement2 = UIView(frame: .mockAny())

        ambiguousChild.addSubview(childOfAmbiguousElement)
        specificChild1.addSubview(childOfSpecificElement1)
        specificChild2.addSubview(childOfSpecificElement2)
        rootView.addSubview(ambiguousChild)
        rootView.addSubview(specificChild1)
        rootView.addSubview(specificChild2)

        let semanticsByView: [UIView: NodeSemantics] = [
            rootView: MockSemantics(recordSubtree: true, debugName: "rootView"),
            ambiguousChild: MockSemantics(recordSubtree: true, debugName: "ambiguousChild"),
            specificChild1: MockSemantics(recordSubtree: true, debugName: "specificChild1"),
            specificChild2: MockSemantics(recordSubtree: false, debugName: "specificChild2"),
            childOfAmbiguousElement: MockSemantics(recordSubtree: true, debugName: "childOfAmbiguousElement"),
            childOfSpecificElement1: MockSemantics(recordSubtree: true, debugName: "childOfSpecificElement1"),
            childOfSpecificElement2: MockSemantics(recordSubtree: false, debugName: "childOfSpecificElement2"),
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])
        let nodes = recorder.recordNodes(for: rootView, in: .mockRandom())

        // Then
        let expectedNodes = ["rootView", "ambiguousChild", "childOfAmbiguousElement", "specificChild1", "childOfSpecificElement1", "specificChild2"]
        let actualNodes = nodes.compactMap { ($0.semantics as? MockSemantics)?.debugName }
        XCTAssertEqual(expectedNodes, actualNodes)

        XCTAssertTrue(nodeRecorder.queriedViews.contains(rootView))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(ambiguousChild))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(specificChild1))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(specificChild2))
        XCTAssertTrue(
            nodeRecorder.queriedViews.contains(childOfAmbiguousElement),
            "It should query `childOfAmbiguousElement`, because the parent has 'recordSubtree: true' semantics"
        )
        XCTAssertTrue(
            nodeRecorder.queriedViews.contains(childOfSpecificElement1),
            "It should query `childOfSpecificElement1`, because the parent has 'specific' semantics with `recordSubtree: true`"
        )
        XCTAssertFalse(
            nodeRecorder.queriedViews.contains(childOfSpecificElement2),
            "It should NOT query `childOfSpecificElement1`, because the parent has 'specific' semantics with `recordSubtree: false`"
        )
    }

    // MARK: - Recording Certain Node Semantics

    func testItRecordsInvisibleViews() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: defaultNodeRecorders)
        let views: [UIView] = [
            UIView.mock(withFixture: .invisible),
            UILabel.mock(withFixture: .invisible),
            UIImageView.mock(withFixture: .invisible),
            UITextField.mock(withFixture: .invisible),
            UISwitch.mock(withFixture: .invisible),
        ]

        // When
        let nodes = views.map { recorder.recordNodes(for: $0, in: .mockRandom()) }

        // Then
        zip(nodes, views).forEach { nodes, view in
            XCTAssertTrue(
                nodes[0].semantics is InvisibleElement,
                """
                All invisible members of `UIView` should record `InvisibleElement` semantics as
                they will not appear in SR anyway. Got \(type(of: nodes[0].semantics)) instead.
                """
            )
        }
    }

    func testItRecordsViewsWithNoAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: defaultNodeRecorders)

        let view = UIView.mock(withFixture: .visible(.noAppearance))
        let label = UILabel.mock(withFixture: .visible(.noAppearance))
        let imageView = UIImageView.mock(withFixture: .visible(.noAppearance))
        let textField = UITextField.mock(withFixture: .visible(.noAppearance))
        let `switch` = UISwitch.mock(withFixture: .visible(.noAppearance))

        // When
        let viewNodes = recorder.recordNodes(for: view, in: .mockRandom())
        XCTAssertEqual(viewNodes.count, 1)
        XCTAssertTrue(
            viewNodes[0].semantics is AmbiguousElement,
            """
            Bare `UIView` with no appearance should record `AmbiguousElement` semantics as we don't know
            if this view is specialised with appearance coming from its superclass.
            Got \(type(of: viewNodes[0].semantics)) instead.
            """
        )

        let labelNodes = recorder.recordNodes(for: label, in: .mockRandom())
        XCTAssertEqual(labelNodes.count, 1)
        XCTAssertTrue(
            labelNodes[0].semantics is InvisibleElement,
            """
            `UILabel` with no appearance should record `InvisibleElement` semantics as it
            won't display anything in SR. Got \(type(of: labelNodes[0].semantics)) instead.
            """
        )

        let imageViewNodes = recorder.recordNodes(for: imageView, in: .mockRandom())
        XCTAssertEqual(imageViewNodes.count, 1)
        XCTAssertTrue(
            imageViewNodes[0].semantics is InvisibleElement,
            """
            `UIImageView` with no appearance should record `InvisibleElement` semantics as it
            won't display anything in SR. Got \(type(of: imageViewNodes[0].semantics)) instead.
            """
        )

        let textFieldNodes = recorder.recordNodes(for: textField, in: .mockRandom())
        XCTAssertEqual(textFieldNodes.count, 1)
        XCTAssertTrue(
            textFieldNodes[0].semantics is SpecificElement,
            """
            `UITextField` with no appearance should still record `SpecificElement` semantics as it
            has style coming from its internal subtree. Got \(type(of: textFieldNodes[0].semantics)) instead.
            """
        )

        let switchNodes = recorder.recordNodes(for: `switch`, in: .mockRandom())
        XCTAssertEqual(switchNodes.count, 1)
        XCTAssertTrue(
            switchNodes[0].semantics is SpecificElement,
            """
            `UISwitch` with no appearance should still record `SpecificElement` semantics as it
            has style coming from its internal subtree. Got \(type(of: switchNodes[0].semantics)) instead.
            """
        )
    }

    func testItRecordsBaseViewWithSomeAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: defaultNodeRecorders)
        let view = UIView.mock(withFixture: .visible())

        // When
        let nodes = recorder.recordNodes(for: view, in: .mockRandom())

        // Then
        XCTAssertTrue(
            nodes[0].semantics is AmbiguousElement,
            """
            Bare `UIView` with no appearance should record `AmbiguousElement` semantics as we don't know
            if this view is specialised with appearance coming from its superclass.
            Got \(type(of: nodes[0].semantics)) instead.
            """
        )
    }

    func testItRecordsSpecialisedViewsWithSomeAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: defaultNodeRecorders)
        let views: [UIView] = [
            UILabel.mock(withFixture: .visible()),
            UIImageView.mock(withFixture: .visible()),
            UITextField.mock(withFixture: .visible()),
            UISwitch.mock(withFixture: .visible()),
            UITabBar.mock(withFixture: .visible()),
            UINavigationBar.mock(withFixture: .visible()),
        ]

        // When
        let nodes = views.map { recorder.recordNodes(for: $0, in: .mockRandom()) }

        // Then
        zip(nodes, views).forEach { nodes, view in
            XCTAssertTrue(
                nodes[0].semantics is SpecificElement,
                """
                All specialised subclasses of `UIView` should record `SpecificElement` semantics as
                long as they are visible. Got \(type(of: nodes[0].semantics)) instead.
                """
            )
        }
    }
}
