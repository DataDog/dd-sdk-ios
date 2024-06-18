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

class RecorderTests: XCTestCase {
    func testAfterCapturingSnapshot_itIsPassesToProcessor() throws {
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom(count: 1)
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom(count: 1)
        let snapshotProcessor = SnapshotProcessorSpy()
        let resourceProcessor = ResourceProcessorSpy()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: snapshotProcessor,
            resourceProcessor: resourceProcessor
        )
        let recorderContext = Recorder.Context.mockRandom()

        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        DDAssertReflectionEqual(snapshotProcessor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
        DDAssertReflectionEqual(snapshotProcessor.processedSnapshots.map { $0.touchSnapshot }, mockTouchSnapshots)
        DDAssertReflectionEqual(resourceProcessor.processedResources.map { $0.resources }, mockViewTreeSnapshots.map { $0.resources })
        DDAssertReflectionEqual(resourceProcessor.processedResources.map { $0.context }, mockViewTreeSnapshots.map { _ in EnrichedResource.Context(recorderContext.applicationID) })
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
            snapshotProcessor: SnapshotProcessorSpy(),
            resourceProcessor: ResourceProcessorSpy()
        )
        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0], recorderContext)
    }

    func testWhenCapturingSnapshots_itUsesAdditionalNodeRecorders() throws {
        let recorderContext: Recorder.Context = .mockRandom()
        let additionalNodeRecorder = SessionReplayNodeRecorderMock()
        let windowObserver = AppWindowObserverMock()
        let viewTreeSnapshotProducer = WindowViewTreeSnapshotProducer(
            windowObserver: windowObserver,
            snapshotBuilder: ViewTreeSnapshotBuilder(additionalNodeRecorders: [additionalNodeRecorder])
        )
        let touchSnapshotProducer = TouchSnapshotProducerMock()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: SnapshotProcessorSpy(),
            resourceProcessor: ResourceProcessorSpy()
        )
        // When
        try recorder.captureNextRecord(recorderContext)

        // Then
        let queryContext = try XCTUnwrap(additionalNodeRecorder.queryContexts.first)
        XCTAssertEqual(queryContext.recorder, recorderContext)
    }
}
#endif
