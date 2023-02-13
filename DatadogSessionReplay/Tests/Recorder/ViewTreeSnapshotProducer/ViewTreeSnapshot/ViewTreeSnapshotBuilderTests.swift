/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

private class NodeRecorderMock: NodeRecorder {
    var queriedViews: Set<UIView> = []
    var queryContexts: [ViewTreeSnapshotBuilder.Context] = []
    var resultForView: (UIView) -> NodeSemantics?

    init(resultForView: @escaping (UIView) -> NodeSemantics?) {
        self.resultForView = resultForView
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        queriedViews.insert(view)
        queryContexts.append(context)
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
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: recorders)
        _ = builder.createSnapshot(of: rootView, with: .mockRandom())

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[1].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[2].queriedViews, [rootView, childView, grandchildView])
    }

    // 👀
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
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: recorders)
        _ = builder.createSnapshot(of: view, with: .mockRandom())

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[1].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[2].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[3].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[4].queriedViews, [], "It should NOT be queried as 'specific' semantics is known")
    }

    func testWhenQueryingNodeRecorders_itPassesAppropriateContext() throws {
        // Given
        let view = UIView(frame: .mockRandom())

        let randomRecorderContext: Recorder.Context = .mockWith()
        let recorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [recorder])

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.date, randomRecorderContext.date)
        XCTAssertEqual(snapshot.rumContext, randomRecorderContext.rumContext)

        let queryContext = try XCTUnwrap(recorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder, randomRecorderContext)
    }

    // MARK: - Recording Nodes Recursively

    func testItQueriesViewTreeRecursively() {
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

        let ambiguousElement = AmbiguousElement(wireframesBuilder: NOPWireframesBuilderMock())
        let specificElement1 = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock(), recordSubtree: true)
        let specificElement2 = SpecificElement(wireframesBuilder: NOPWireframesBuilderMock(), recordSubtree: false)

        let semanticsByView: [UIView: NodeSemantics] = [
            rootView: ambiguousElement,
            ambiguousChild: ambiguousElement,
            specificChild1: specificElement1,
            specificChild2: specificElement2,
            childOfAmbiguousElement: ambiguousElement,
            childOfSpecificElement1: specificElement1,
            childOfSpecificElement2: specificElement2,
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [nodeRecorder])
        let snapshot = builder.createSnapshot(of: rootView, with: .mockRandom())

        // Then
        XCTAssertTrue(snapshot.root.semantics is AmbiguousElement)
        XCTAssertEqual(snapshot.root.children.count, 3)
        XCTAssertTrue(snapshot.root.children[0].semantics is AmbiguousElement)
        XCTAssertTrue(snapshot.root.children[1].semantics is SpecificElement)
        XCTAssertTrue(snapshot.root.children[2].semantics is SpecificElement)
        XCTAssertEqual(snapshot.root.children[0].children.count, 1, "It should record this sub-tree as parent node has 'ambiguous' semantics")
        XCTAssertEqual(snapshot.root.children[1].children.count, 1, "It should record this sub-tree as parent has 'specific' semantics with `recordSubtree: true`")
        XCTAssertEqual(snapshot.root.children[2].children.count, 0, "It should NOT record this sub-tree as parent has 'specific' semantics with `recordSubtree: false`")

        XCTAssertTrue(nodeRecorder.queriedViews.contains(rootView))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(ambiguousChild))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(specificChild1))
        XCTAssertTrue(nodeRecorder.queriedViews.contains(specificChild2))
        XCTAssertTrue(
            nodeRecorder.queriedViews.contains(childOfAmbiguousElement),
            "It should query `childOfAmbiguousElement`, because the parent has 'ambiguous' semantics"
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
        let builder = ViewTreeSnapshotBuilder()
        let views: [UIView] = [
            UIView.mock(withFixture: .invisible),
            UILabel.mock(withFixture: .invisible),
            UIImageView.mock(withFixture: .invisible),
            UITextField.mock(withFixture: .invisible),
            UISwitch.mock(withFixture: .invisible),
        ]

        // When
        let snapshots = views.map { builder.createSnapshot(of: $0, with: .mockRandom()) }

        // Then
        zip(snapshots, views).forEach { snapshot, view in
            XCTAssertTrue(
                snapshot.root.semantics is InvisibleElement,
                """
                All invisible members of `UIView` should record `InvisibleElement` semantics as
                they will not appear in SR anyway. Got \(type(of: snapshot.root.semantics)) instead.
                """
            )
        }
    }

    func testItRecordsViewsWithNoAppearance() {
        // Given
        let builder = ViewTreeSnapshotBuilder()

        let view = UIView.mock(withFixture: .visible(.noAppearance))
        let label = UILabel.mock(withFixture: .visible(.noAppearance))
        let imageView = UIImageView.mock(withFixture: .visible(.noAppearance))
        let textField = UITextField.mock(withFixture: .visible(.noAppearance))
        let `switch` = UISwitch.mock(withFixture: .visible(.noAppearance))

        // When
        let viewSnapshot = builder.createSnapshot(of: view, with: .mockRandom())
        XCTAssertTrue(
            viewSnapshot.root.semantics is AmbiguousElement,
            """
            Bare `UIView` with no appearance should record `AmbiguousElement` semantics as we don't know
            if this view is specialised with appearance coming from its superclass.
            Got \(type(of: viewSnapshot.root.semantics)) instead.
            """
        )

        let labelSnapshot = builder.createSnapshot(of: label, with: .mockRandom())
        XCTAssertTrue(
            labelSnapshot.root.semantics is InvisibleElement,
            """
            `UILabel` with no appearance should record `InvisibleElement` semantics as it
            won't display anything in SR. Got \(type(of: labelSnapshot.root.semantics)) instead.
            """
        )

        let imageViewSnapshot = builder.createSnapshot(of: imageView, with: .mockRandom())
        XCTAssertTrue(
            imageViewSnapshot.root.semantics is InvisibleElement,
            """
            `UIImageView` with no appearance should record `InvisibleElement` semantics as it
            won't display anything in SR. Got \(type(of: imageViewSnapshot.root.semantics)) instead.
            """
        )

        let textFieldSnapshot = builder.createSnapshot(of: textField, with: .mockRandom())
        XCTAssertTrue(
            textFieldSnapshot.root.semantics is SpecificElement,
            """
            `UITextField` with no appearance should still record `SpecificElement` semantics as it
            has style coming from its internal subtree. Got \(type(of: textFieldSnapshot.root.semantics)) instead.
            """
        )

        let switchSnapshot = builder.createSnapshot(of: `switch`, with: .mockRandom())
        XCTAssertTrue(
            switchSnapshot.root.semantics is SpecificElement,
            """
            `UISwitch` with no appearance should still record `SpecificElement` semantics as it
            has style coming from its internal subtree. Got \(type(of: switchSnapshot.root.semantics)) instead.
            """
        )
    }

    func testItRecordsBaseViewWithSomeAppearance() {
        // Given
        let builder = ViewTreeSnapshotBuilder()
        let view = UIView.mock(withFixture: .visible())

        // When
        let snapshot = builder.createSnapshot(of: view, with: .mockRandom())

        // Then
        XCTAssertTrue(
            snapshot.root.semantics is AmbiguousElement,
            """
            Bare `UIView` with no appearance should record `AmbiguousElement` semantics as we don't know
            if this view is specialised with appearance coming from its superclass.
            Got \(type(of: snapshot.root.semantics)) instead.
            """
        )
    }

    func testItRecordsSpecialisedViewsWithSomeAppearance() {
        // Given
        let builder = ViewTreeSnapshotBuilder()
        let views: [UIView] = [
            UILabel.mock(withFixture: .visible()),
            UIImageView.mock(withFixture: .visible()),
            UITextField.mock(withFixture: .visible()),
            UISwitch.mock(withFixture: .visible()),
            UITabBar.mock(withFixture: .visible()),
            UINavigationBar.mock(withFixture: .visible()),
        ]

        // When
        let snapshots = views.map { builder.createSnapshot(of: $0, with: .mockRandom()) }

        // Then
        zip(snapshots, views).forEach { snapshot, view in
            XCTAssertTrue(
                snapshot.root.semantics is SpecificElement,
                """
                All specialised subclasses of `UIView` should record `SpecificElement` semantics as
                long as they are visible. Got \(type(of: snapshot.root.semantics)) instead.
                """
            )
        }
    }

    func testItAppliesServerTimeOffsetIsToSnapshot() {
        // Given
        let now = Date()
        let view = UIView(frame: .mockRandom())

        // When
        let recorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [recorder])
        let snapshot = builder.createSnapshot(of: view, with: .mockWith(date: now, rumContext: .mockWith(serverTimeOffset: 1_000)))

        // Then
        XCTAssertGreaterThan(snapshot.date, now)
    }
}
