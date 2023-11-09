/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SafariServices

@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

private struct MockSemantics: NodeSemantics {
    static var importance: Int = .mockAny()
    var subtreeStrategy: NodeSubtreeStrategy
    var nodes: [Node]

    init(subtreeStrategy: NodeSubtreeStrategy, nodeNames: [String]) {
        self.subtreeStrategy = subtreeStrategy
        self.nodes = nodeNames.map {
            Node(viewAttributes: .mockAny(), wireframesBuilder: MockWireframesBuilder(nodeName: $0))
        }
    }
}

private struct MockWireframesBuilder: NodeWireframesBuilder {
    let nodeName: String
    var wireframeRect: CGRect = .mockAny()
    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] { [] }
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
        let ambiguousElement = AmbiguousElement(nodes: .mockAny())
        let specificElement = SpecificElement(subtreeStrategy: .mockRandom(), nodes: .mockAny())

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
            rootView: MockSemantics(subtreeStrategy: .record, nodeNames: ["rootView"]),
            a: MockSemantics(subtreeStrategy: .record, nodeNames: ["a"]),
            b: MockSemantics(subtreeStrategy: .record, nodeNames: ["b"]),
            c: MockSemantics(subtreeStrategy: .ignore, nodeNames: ["c"]), // ignore subtree of `c`
            aa: MockSemantics(subtreeStrategy: .ignore, nodeNames: ["aa", "aav1", "aav2", "aav3"]), // replace `aaa` (subtree of `aa`) with 3 nodes
            ab: MockSemantics(subtreeStrategy: .record, nodeNames: ["ab"]),
            aba: MockSemantics(subtreeStrategy: .record, nodeNames: ["aba"]),
            abb: MockSemantics(subtreeStrategy: .record, nodeNames: ["abb"]),
            ca: MockSemantics(subtreeStrategy: .record, nodeNames: ["ca"]),
            cb: MockSemantics(subtreeStrategy: .record, nodeNames: ["cb"]),
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])
        let nodes = recorder.recordNodes(for: rootView, in: .mockRandom())

        // Then
        let expectedNodes = ["rootView", "a", "aa", "aav1", "aav2", "aav3", "ab", "aba", "abb", "b", "c"]
        let actualNodes = nodes.compactMap { ($0.wireframesBuilder as? MockWireframesBuilder)?.nodeName }
        XCTAssertEqual(expectedNodes, actualNodes, "Nodes must be recorded in DFS order")

        let expectedQueriedViews: [UIView] = [rootView, a, b, c, aa, ab, aba, abb]
        XCTAssertEqual(nodeRecorder.queriedViews.count, expectedQueriedViews.count)
        expectedQueriedViews.forEach { XCTAssertTrue(nodeRecorder.queriedViews.contains($0)) }

        let expectedSkippedViews: [UIView] = [aaa, ca, cb]
        expectedSkippedViews.forEach { XCTAssertFalse(nodeRecorder.queriedViews.contains($0)) }
    }

    // MARK: - Recording Certain Node Semantics

    func testItRecordsInvisibleViews() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders())
        let views: [UIView] = [
            UIView.mock(withFixture: .invisible),
            UILabel.mock(withFixture: .invisible),
            UIImageView.mock(withFixture: .invisible),
            UITextField.mock(withFixture: .invisible),
            UISwitch.mock(withFixture: .invisible),
        ]

        views.forEach { view in
            // When
            let nodes = recorder.recordNodes(for: view, in: .mockRandom())

            // Then
            XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for \(type(of: view)) when it is not visible")
        }
    }

    func testItRecordsViewsWithNoAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders())

        let view = UIView.mock(withFixture: .visible(.noAppearance))
        let label = UILabel.mock(withFixture: .visible(.noAppearance))
        let imageView = UIImageView.mock(withFixture: .visible(.noAppearance))
        let textField = UITextField.mock(withFixture: .visible(.noAppearance))
        let `switch` = UISwitch.mock(withFixture: .visible(.noAppearance))

        // When
        let viewNodes = recorder.recordNodes(for: view, in: .mockRandom())
        XCTAssertTrue(viewNodes.isEmpty, "No nodes should be recorded for `UIView` when it has no appearance")

        let labelNodes = recorder.recordNodes(for: label, in: .mockRandom())
        XCTAssertTrue(labelNodes.isEmpty, "No nodes should be recorded for `UILabel` when it has no appearance")

        let imageViewNodes = recorder.recordNodes(for: imageView, in: .mockRandom())
        XCTAssertTrue(imageViewNodes.isEmpty, "No nodes should be recorded for `UIImageView` when it has no appearance")

        let textFieldNodes = recorder.recordNodes(for: textField, in: .mockRandom())
        XCTAssertTrue(textFieldNodes.isEmpty, "No nodes should be recorded for `UITextField` when it has no appearance")

        let switchNodes = recorder.recordNodes(for: `switch`, in: .mockRandom())
        XCTAssertFalse(
            switchNodes.isEmpty,
            "`UISwitch` with no appearance should record some nodes as it has style coming from its internal subtree."
        )
    }

    func testItRecordsViewsWithSomeAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders())
        let views: [UIView] = [
            UIView.mock(withFixture: .visible(.someAppearance)),
            UILabel.mock(withFixture: .visible(.someAppearance)),
            UIImageView.mock(withFixture: .visible(.someAppearance)),
            UITextField.mock(withFixture: .visible(.someAppearance)),
            UISwitch.mock(withFixture: .visible(.someAppearance)),
            UITabBar.mock(withFixture: .visible(.someAppearance)),
            UINavigationBar.mock(withFixture: .visible(.someAppearance)),
        ]

        views.forEach { view in
            // When
            let nodes = recorder.recordNodes(for: view, in: .mockRandom())

            // Then
            XCTAssertFalse(nodes.isEmpty, "Some nodes should be recorded for \(type(of: view)) when it has some appearance")
        }
    }

    func testItOverridesViewControllerContext() {
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])
        let views = [
            UIAlertController(title: "", message: "", preferredStyle: .alert).view,
            UIView(),
            UIViewController().view,
            UIView(),
            SFSafariViewController(url: .mockRandom()).view,
            UIView(),
            UIActivityViewController(activityItems: [], applicationActivities: nil).view,
            UIView()
        ].compactMap { $0 }

        zip(views, views.dropFirst()).forEach {
            $0.0.addSubview($0.1)
        }

        // When
        _ = recorder.recordNodes(for: views.first!, in: .mockRandom())

        // Then
        var context = nodeRecorder.queryContextsByView[views[0]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .alert)

        context = nodeRecorder.queryContextsByView[views[1]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .alert)

        context = nodeRecorder.queryContextsByView[views[2]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .other)

        context = nodeRecorder.queryContextsByView[views[3]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .other)

        context = nodeRecorder.queryContextsByView[views[4]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .safari)

        context = nodeRecorder.queryContextsByView[views[5]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .safari)

        context = nodeRecorder.queryContextsByView[views[6]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .activity)

        context = nodeRecorder.queryContextsByView[views[7]]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .activity)
    }
}
