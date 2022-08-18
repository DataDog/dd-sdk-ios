/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

private typealias Frame = ViewTreeSnapshot.Node.Frame

class ViewTreeSnapshotBuilderTests: XCTestCase {
    private let builder = ViewTreeSnapshotBuilder()

    // MARK: - Computing Frames

    func testComputingFrameWhenRootViewHasNoSubviews() throws {
        // Given
        let rootView = UIView(frame: .mockRandom())
        XCTAssertEqual(rootView.subviews.count, 0)

        // When
        let snapshot = try builder.createSnapshot(of: rootView)

        // Then
        XCTAssertTrue(snapshot.root.children.isEmpty, "It should have no children")

        XCTAssertEqual(snapshot.root.frame.x, 0, "The root view should always start at (0, 0)")
        XCTAssertEqual(snapshot.root.frame.y, 0, "The root view should always start at (0, 0)")
        XCTAssertEqual(snapshot.root.frame.width, Int64(withNoOverflow: rootView.frame.width))
        XCTAssertEqual(snapshot.root.frame.height, Int64(withNoOverflow: rootView.frame.height))
    }

    func testComputingFramesWhenRootViewHasNestedSubviews() throws {
        // Given
        let rootView = UIView(frame: .mockRandom())
        let childView = UIView(frame: .mockRandom())
        let grandchildView = UIView(frame: .mockRandom())
        childView.addSubview(grandchildView)
        rootView.addSubview(childView)

        // When
        let snapshot = try builder.createSnapshot(of: rootView)

        // Then
        XCTAssertEqual(snapshot.root.children.count, 1)
        XCTAssertEqual(snapshot.root.children[0].children.count, 1)
        XCTAssertEqual(snapshot.root.children[0].children[0].children.count, 0)

        XCTAssertEqual(
            snapshot.root.frame,
            Frame(
                x: 0,
                y: 0,
                width: Int64(withNoOverflow: rootView.frame.width),
                height: Int64(withNoOverflow: rootView.frame.height)
            )
        )
        XCTAssertEqual(
            snapshot.root.children[0].frame,
            Frame(
                x: Int64(withNoOverflow: childView.frame.origin.x),
                y: Int64(withNoOverflow: childView.frame.origin.y),
                width: Int64(withNoOverflow: childView.frame.width),
                height: Int64(withNoOverflow: childView.frame.height)
            ),
            "The position of nested snapshots should be given in root's coordinate space"
        )
        XCTAssertEqual(
            snapshot.root.children[0].children[0].frame,
            Frame(
                x: Int64(withNoOverflow: childView.frame.origin.x + grandchildView.frame.origin.x),
                y: Int64(withNoOverflow: childView.frame.origin.y + grandchildView.frame.origin.y),
                width: Int64(withNoOverflow: grandchildView.frame.width),
                height: Int64(withNoOverflow: grandchildView.frame.height)
            ),
            "The position of nested snapshots should be given in root's coordinate space"
        )
    }
}
