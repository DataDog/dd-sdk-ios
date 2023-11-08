/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal) @testable import DatadogSessionReplay
@testable import TestUtilities

class ViewTreeSnapshotBuilderTests: XCTestCase {
    func testWhenQueryingNodeRecorders_itPassesAppropriateContext() throws {
        // Given
        let view = UIView(frame: .mockRandom())
        let randomRecorderContext: Recorder.Context = .mockRandom()
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator(),
            imageDataProvider: MockImageDataProvider()
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.context, randomRecorderContext)

        let queryContext = try XCTUnwrap(nodeRecorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder, randomRecorderContext)
    }

    func testItAppliesServerTimeOffsetToSnapshot() {
        // Given
        let now = Date()
        let view = UIView(frame: .mockRandom())
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator(),
            imageDataProvider: MockImageDataProvider()
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: .mockWith(date: now, rumContext: .mockWith(serverTimeOffset: 1_000)))

        // Then
        XCTAssertGreaterThan(snapshot.date, now)
    }
}
