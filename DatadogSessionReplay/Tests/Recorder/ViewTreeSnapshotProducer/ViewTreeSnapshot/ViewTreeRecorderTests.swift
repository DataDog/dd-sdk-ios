/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

private struct MockSemantics: NodeSemantics {
    static var importance: Int = .mockAny()
    var subtreeStrategy: NodeSubtreeStrategy
    var wireframesBuilder: NodeWireframesBuilder? = nil
    let debugName: String
}

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

    func testItQueriesNodeRecordersUntilOneFindsBestSemantics() {
        // Given
        let view = UIView(frame: .mockRandom())

        let unknownElement = UnknownElement.constant
        let ambiguousElement = AmbiguousElement(wireframesBuilder: NOPWireframesBuilderMock())
        let specificElement = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock(), subtreeStrategy: .mockRandom())

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
        // Given

        /*
                rootView
                /   |   \
               /    |    \
               a    b     c
              / \        / \
             aa ab      ca cb
             /  / \
          aaa aba abb
        */

        let rootView = UIView.mockAny()
        let (a, b, c) = (UIView.mockAny(), UIView.mockAny(), UIView.mockAny())
        let (aa, aaa, ab, aba, abb) = (UIView.mockAny(), UIView.mockAny(), UIView.mockAny(), UIView.mockAny(), UIView.mockAny())
        let (ca, cb) = (UIView.mockAny(), UIView.mockAny())

        rootView.addSubview(a)
        rootView.addSubview(b)
        rootView.addSubview(c)
        a.addSubview(aa)
        aa.addSubview(aaa)
        a.addSubview(ab)
        ab.addSubview(aba)
        ab.addSubview(abb)
        c.addSubview(ca)
        c.addSubview(cb)

        let semanticsByView: [UIView: NodeSemantics] = [
            rootView: MockSemantics(subtreeStrategy: .record, debugName: "rootView"),
            a: MockSemantics(subtreeStrategy: .record, debugName: "a"),
            b: MockSemantics(subtreeStrategy: .record, debugName: "b"),
            c: MockSemantics(subtreeStrategy: .ignore, debugName: "c"), // The subtree of `c` should be ignored
            aa: MockSemantics(
                // The subtree of `aa` (`aaa`) should be replaced with 3 virtual nodes:
                subtreeStrategy: .replace(
                    subtreeNodes: [
                        .mockWith(semantics: MockSemantics(subtreeStrategy: .record, debugName: "aav1")),
                        .mockWith(semantics: MockSemantics(subtreeStrategy: .record, debugName: "aav2")),
                        .mockWith(semantics: MockSemantics(subtreeStrategy: .record, debugName: "aav3")),
                    ]
                ),
                debugName: "aa"
            ),
            ab: MockSemantics(subtreeStrategy: .record, debugName: "ab"),
            aba: MockSemantics(subtreeStrategy: .record, debugName: "aba"),
            abb: MockSemantics(subtreeStrategy: .record, debugName: "abb"),
            ca: MockSemantics(subtreeStrategy: .record, debugName: "ca"),
            cb: MockSemantics(subtreeStrategy: .record, debugName: "cb"),
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])
        let nodes = recorder.recordNodes(for: rootView, in: .mockRandom())

        // Then
        let expectedNodes = ["rootView", "a", "aa", "aav1", "aav2", "aav3", "ab", "aba", "abb", "b", "c"]
        let actualNodes = nodes.compactMap { ($0.semantics as? MockSemantics)?.debugName }
        XCTAssertEqual(expectedNodes, actualNodes, "Nodes must be recorded in DFS order")

        let expectedQueriedViews: [UIView] = [rootView, a, b, c, aa, ab, aba, abb]
        XCTAssertEqual(nodeRecorder.queriedViews.count, expectedQueriedViews.count)
        expectedQueriedViews.forEach { XCTAssertTrue(nodeRecorder.queriedViews.contains($0)) }

        let expectedSkippedViews: [UIView] = [aaa, ca, cb]
        expectedSkippedViews.forEach { XCTAssertFalse(nodeRecorder.queriedViews.contains($0)) }
    }

    // MARK: - Recording Certain Node Semantics

    func testWhenChildNodeSemanticsIsFound_itCanBeOverwrittenByParent() {
        // Given
        let view = UIView.mockAny()
        let semantics = MockSemantics(subtreeStrategy: .record, debugName: "original")
        let recorder = ViewTreeRecorder(
            nodeRecorders: [
                NodeRecorderMock(resultForView: { _ in semantics })
            ]
        )

        // When
        var context: ViewTreeRecordingContext = .mockRandom()
        context.semanticsOverride = { currentSemantis, currentView, viewAttributes in
            XCTAssertEqual((currentSemantis as? MockSemantics)?.debugName, "original")
            XCTAssertTrue(currentView === view)
            return MockSemantics(subtreeStrategy: .record, debugName: "overwritten")
        }
        let nodes = recorder.recordNodes(for: view, in: context)

        // Then
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual((nodes[0].semantics as? MockSemantics)?.debugName, "overwritten")
    }

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
            viewNodes[0].semantics is InvisibleElement,
            """
            Bare `UIView` with no appearance should record `InvisibleElement` semantics as we don't know
            if this view is specialised with appearance coming from its superclass.
            Got \(type(of: viewNodes[0].semantics)) instead.
            """
        )
        DDAssertReflectionEqual(
            viewNodes[0].semantics.subtreeStrategy,
            .record,
            """
            For bare `UIView` with no appearance it should still record its sub-tree hierarchy as it might
            contain other visible elements.
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
