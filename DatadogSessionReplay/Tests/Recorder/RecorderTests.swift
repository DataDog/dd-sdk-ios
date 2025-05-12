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

class RecorderTests: XCTestCase {
    func testAfterCapturingSnapshot_itIsPassesToProcessor() throws {
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom(count: 1)
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom(count: 1)
        let snapshotProcessor = SnapshotProcessorSpy()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: snapshotProcessor
        )
        let recorderContext = Recorder.Context.mockRandom()

        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        DDAssertReflectionEqual(snapshotProcessor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
    }

    func testWhenCapturingSnapshots_itUsesDefaultRecorderContext() throws {
        let recorderContext: Recorder.Context = .mockRandom()
        let viewTreeSnapshotProducer = ViewTreeSnapshotProducerSpy()
        let touchSnapshotProducer = TouchSnapshotProducerMock()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: SnapshotProcessorSpy()
        )
        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts.count, 1)
        let context = try XCTUnwrap(viewTreeSnapshotProducer.succeedingContexts.first)
        XCTAssertEqual(context.applicationID, recorderContext.applicationID)
        XCTAssertEqual(context.sessionID, recorderContext.sessionID)
        XCTAssertEqual(context.viewID, recorderContext.viewID)
        XCTAssertEqual(context.viewServerTimeOffset, recorderContext.viewServerTimeOffset)
        XCTAssertEqual(context.date, recorderContext.date)
    }

    func testWhenCapturingSnapshots_itUsesAdditionalNodeRecorders() throws {
        let recorderContext: Recorder.Context = .mockRandom()
        let additionalNodeRecorder = SessionReplayNodeRecorderMock()
        let windowObserver = AppWindowObserverMock()
        let viewTreeSnapshotProducer = WindowViewTreeSnapshotProducer(
            windowObserver: windowObserver,
            snapshotBuilder: ViewTreeSnapshotBuilder(additionalNodeRecorders: [additionalNodeRecorder], featureFlags: .allEnabled)
        )
        let touchSnapshotProducer = TouchSnapshotProducerMock()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: SnapshotProcessorSpy()
        )
        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        let queryContext = try XCTUnwrap(additionalNodeRecorder.queryContexts.first?.recorder)
        XCTAssertEqual(queryContext.applicationID, recorderContext.applicationID)
        XCTAssertEqual(queryContext.sessionID, recorderContext.sessionID)
        XCTAssertEqual(queryContext.viewID, recorderContext.viewID)
        XCTAssertEqual(queryContext.viewServerTimeOffset, recorderContext.viewServerTimeOffset)
        XCTAssertEqual(queryContext.date, recorderContext.date)
    }

    // MARK: Touch Snapshot Recording
    func testAfterCapturingSnapshot_withTouchPrivacyShow_itIsPassesToProcessor() throws {
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom(count: 1)
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom(count: 1)
        let snapshotProcessor = SnapshotProcessorSpy()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: snapshotProcessor
        )
        let recorderContext = Recorder.Context.mockWith(
            touchPrivacy: .show
        )

        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        DDAssertReflectionEqual(snapshotProcessor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
        XCTAssertEqual(snapshotProcessor.processedSnapshots.compactMap { $0.touchSnapshot }.count, mockTouchSnapshots.count)
    }

    func testAfterCapturingSnapshot_withTouchPrivacyHide_itDoesNotPassToProcessor() throws {
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom(count: 1)
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom(count: 0)
        let snapshotProcessor = SnapshotProcessorSpy()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: snapshotProcessor
        )
        let recorderContext = Recorder.Context.mockWith(
            touchPrivacy: .hide
        )

        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        DDAssertReflectionEqual(snapshotProcessor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
        XCTAssertEqual(snapshotProcessor.processedSnapshots.compactMap { $0.touchSnapshot }.count, mockTouchSnapshots.count)
    }
}
#endif
