/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class RecorderTests: XCTestCase {
    func testAfterCapturingSnapshot_itIsPassesToProcessor() {
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom()
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom()
        let processor = ProcessorSpy()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: processor,
            telemetry: TelemetryMock()
        )
        // When
        recorder.captureNextRecord(.mockRandom())

        // Then
        DDAssertReflectionEqual(processor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
        DDAssertReflectionEqual(processor.processedSnapshots.map { $0.touchSnapshot }, mockTouchSnapshots)
    }

    func testWhenCapturingSnapshots_itUsesDefaultRecorderContext() {
        let recorderContext: Recorder.Context = .mockRandom()
        let viewTreeSnapshotProducer = ViewTreeSnapshotProducerSpy()
        let touchSnapshotProducer = TouchSnapshotProducerMock()

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: ProcessorSpy(),
            telemetry: TelemetryMock()
        )
        // When
        recorder.captureNextRecord(recorderContext)

        // Then
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0], recorderContext)
    }

    func testWhenCapturingSnapshotFails_itSendsErrorTelemetry() {
        let telemetry = TelemetryMock()
        let viewTreeSnapshotProducer = ViewTreeSnapshotProducerMock(
            succeedingErrors: [ErrorMock("snapshot creation error")]
        )

        // Given
        let recorder = Recorder(
            uiApplicationSwizzler: .mockAny(),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: TouchSnapshotProducerMock(),
            snapshotProcessor: ProcessorSpy(),
            telemetry: telemetry
        )

        // When
        recorder.captureNextRecord(.mockRandom())

        // Then
        XCTAssertEqual(
            telemetry.description,
            """
            Telemetry logs:
             - [error] [SR] Failed to take snapshot - snapshot creation error, kind: ErrorMock, stack: snapshot creation error
            """
        )
    }
}
