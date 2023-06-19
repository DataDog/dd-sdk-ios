/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class RecorderTests: XCTestCase {
    private var recorder: Recorder?

    override func tearDown() {
        recorder = nil
    }

    func testGivenRUMContextAvailable_whenStarted_itCapturesSnapshotsAndPassesThemToProcessor() {
        let numberOfSnapshots = 10
        let mockViewTreeSnapshots: [ViewTreeSnapshot] = .mockRandom(count: numberOfSnapshots)
        let mockTouchSnapshots: [TouchSnapshot] = .mockRandom(count: numberOfSnapshots)
        let processor = ProcessorSpy()
        let scheduler = TestScheduler(numberOfRepeats: numberOfSnapshots)

        // Given
        recorder = Recorder(
            configuration: .mockAny(),
            uiApplicationSwizzler: .mockAny(),
            scheduler: scheduler,
            recordingCoordinator: RecordingCoordinationMock(currentRUMContext: .mockRandom()),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: mockViewTreeSnapshots),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: mockTouchSnapshots),
            snapshotProcessor: processor
        )

        // When
        scheduler.start()

        // Then
        DDAssertReflectionEqual(processor.processedSnapshots.count, numberOfSnapshots, "Processor should receive \(numberOfSnapshots) snapshots")
        DDAssertReflectionEqual(processor.processedSnapshots.map { $0.viewTreeSnapshot }, mockViewTreeSnapshots)
        DDAssertReflectionEqual(processor.processedSnapshots.map { $0.touchSnapshot }, mockTouchSnapshots)
    }

    func testGivenNoRUMContextAvailable_whenStarted_itDoesNotCaptureAnySnapshots() {
        let processor = ProcessorSpy()
        let scheduler = TestScheduler()

        // Given
        recorder = Recorder(
            configuration: .mockAny(),
            uiApplicationSwizzler: .mockAny(),
            scheduler: scheduler,
            recordingCoordinator: RecordingCoordinationMock(currentRUMContext: nil),
            viewTreeSnapshotProducer: ViewTreeSnapshotProducerMock(succeedingSnapshots: .mockAny(count: 1)),
            touchSnapshotProducer: TouchSnapshotProducerMock(succeedingSnapshots: .mockAny(count: 1)),
            snapshotProcessor: processor
        )

        // When
        scheduler.start()

        // Then
        XCTAssertTrue(processor.processedSnapshots.isEmpty)
    }

    func testGivenRUMContextAvailable_whenCapturingSnapshots_itUsesDefaultRecorderContext() {
        let randomPrivacy: SessionReplayPrivacy = .mockRandom()
        let randomRUMContext: RUMContext = .mockRandom()
        let viewTreeSnapshotProducer = ViewTreeSnapshotProducerSpy()
        let touchSnapshotProducer = TouchSnapshotProducerMock()
        let scheduler = TestScheduler()

        // Given
        recorder = Recorder(
            configuration: SessionReplayConfiguration(privacy: randomPrivacy),
            uiApplicationSwizzler: .mockAny(),
            scheduler: scheduler,
            recordingCoordinator: RecordingCoordinationMock(currentRUMContext: randomRUMContext),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: ProcessorSpy()
        )

        // When
        scheduler.start()

        // Then
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0].privacy, randomPrivacy)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0].rumContext, randomRUMContext)
    }

    func testGivenRUMContextAvailable_whenCapturingSnapshots_itUsesCurrentRecorderContext() {
        let viewTreeSnapshotProducer = ViewTreeSnapshotProducerSpy()
        let touchSnapshotProducer = TouchSnapshotProducerMock()
        let currentRUMContext: RUMContext = .mockRandom()
        let scheduler = TestScheduler()

        // Given
        recorder = Recorder(
            configuration: SessionReplayConfiguration(privacy: .mockRandom()),
            uiApplicationSwizzler: .mockAny(),
            scheduler: scheduler,
            recordingCoordinator: RecordingCoordinationMock(currentRUMContext: currentRUMContext),
            viewTreeSnapshotProducer: viewTreeSnapshotProducer,
            touchSnapshotProducer: touchSnapshotProducer,
            snapshotProcessor: ProcessorSpy()
        )

        // When
        let currentPrivacy: SessionReplayPrivacy = .mockRandom()
        recorder?.change(privacy: currentPrivacy)

        scheduler.start()

        // Then
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0].privacy, currentPrivacy)
        XCTAssertEqual(viewTreeSnapshotProducer.succeedingContexts[0].rumContext, currentRUMContext)
    }
}
