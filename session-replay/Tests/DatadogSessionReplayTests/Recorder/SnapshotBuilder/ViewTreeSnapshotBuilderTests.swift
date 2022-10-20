/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

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

        let randomSnapshotOptions: ViewTreeSnapshotOptions = .mockRandom()
        let recorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [recorder])

        // When
        _ = builder.createSnapshot(of: view, with: randomSnapshotOptions)

        // Then
        let queryContext = try XCTUnwrap(recorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.options, randomSnapshotOptions)
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
        let builder = ViewTreeSnapshotBuilder(nodeRecorders: [nodeRecorder])
        let snapshot = builder.createSnapshot(of: rootView, with: .mockRandom())

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

    // MARK: - Recording Certain Node Semantics

    func testItRecordsInvisibleViews() throws {
        // Given
        let builder = ViewTreeSnapshotBuilder()
        let views: [UIView] = [
            try UIView.mock(withFixture: .invisible),
            try UILabel.mock(withFixture: .invisible),
            try UIImageView.mock(withFixture: .invisible),
            try UITextField.mock(withFixture: .invisible),
            try UISwitch.mock(withFixture: .invisible),
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

    func testItRecordsViewsWithNoAppearance() throws {
        // Given
        let builder = ViewTreeSnapshotBuilder()

        let view = try UIView.mock(withFixture: .visibleWithNoAppearance)
        let label = try UILabel.mock(withFixture: .visibleWithNoAppearance)
        let imageView = try UIImageView.mock(withFixture: .visibleWithNoAppearance)
        let textField = try UITextField.mock(withFixture: .visibleWithNoAppearance)
        let `switch` = try UISwitch.mock(withFixture: .visibleWithNoAppearance)

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

    func testItRecordsBaseViewWithSomeAppearance() throws {
        // Given
        let builder = ViewTreeSnapshotBuilder()
        let view = try UIView.mock(withFixture: .visibleWithSomeAppearance)

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

    func testItRecordsSpecialisedViewsWithSomeAppearance() throws {
        // Given
        let builder = ViewTreeSnapshotBuilder()
        let views: [UIView] = [
            try UILabel.mock(withFixture: .visibleWithSomeAppearance),
            try UIImageView.mock(withFixture: .visibleWithSomeAppearance),
            try UITextField.mock(withFixture: .visibleWithSomeAppearance),
            try UISwitch.mock(withFixture: .visibleWithSomeAppearance),
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
}
