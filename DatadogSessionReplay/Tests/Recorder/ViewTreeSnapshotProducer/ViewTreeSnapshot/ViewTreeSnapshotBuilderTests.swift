/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

class ViewTreeSnapshotBuilderTests: XCTestCase {
    func testWhenQueryingNodeRecorders_itPassesAppropriateContext() throws {
        // Given
        let view = UIView(frame: .mockRandom())
        let randomRecorderContext: Recorder.Context = .mockRandom()
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator()
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.context.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(snapshot.context.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(snapshot.context.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(snapshot.context.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(snapshot.context.date, randomRecorderContext.date)

        let queryContext = try XCTUnwrap(nodeRecorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(queryContext.recorder.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(queryContext.recorder.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(queryContext.recorder.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(queryContext.recorder.date, randomRecorderContext.date)
    }

    func testItAppliesServerTimeOffsetToSnapshot() {
        // Given
        let now = Date()
        let view = UIView(frame: .mockRandom())
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(
            viewTreeRecorder: ViewTreeRecorder(nodeRecorders: [nodeRecorder]),
            idsGenerator: NodeIDGenerator()
        )

        // When
        let snapshot = builder.createSnapshot(of: view, with: .mockWith(date: now, rumContext: .mockWith(serverTimeOffset: 1_000)))

        // Then
        XCTAssertGreaterThan(snapshot.date, now)
    }

    func testWhenQueryingNodeRecorders_itCallsAdditionalNodeRecorders() throws {
        // Given
        let view = UIView(frame: .mockRandom())
        let randomRecorderContext: Recorder.Context = .mockRandom()
        let additionalNodeRecorder = SessionReplayNodeRecorderMock(resultForView: { _ in nil })
        let builder = ViewTreeSnapshotBuilder(additionalNodeRecorders: [additionalNodeRecorder], featureFlags: .allEnabled)

        // When
        let snapshot = builder.createSnapshot(of: view, with: randomRecorderContext)

        // Then
        XCTAssertEqual(snapshot.context.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(snapshot.context.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(snapshot.context.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(snapshot.context.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(snapshot.context.date, randomRecorderContext.date)

        let queryContext = try XCTUnwrap(additionalNodeRecorder.queryContexts.first)
        XCTAssertTrue(queryContext.coordinateSpace === view)
        XCTAssertEqual(queryContext.recorder.applicationID, randomRecorderContext.applicationID)
        XCTAssertEqual(queryContext.recorder.sessionID, randomRecorderContext.sessionID)
        XCTAssertEqual(queryContext.recorder.viewID, randomRecorderContext.viewID)
        XCTAssertEqual(queryContext.recorder.viewServerTimeOffset, randomRecorderContext.viewServerTimeOffset)
        XCTAssertEqual(queryContext.recorder.date, randomRecorderContext.date)
    }
}
#endif
