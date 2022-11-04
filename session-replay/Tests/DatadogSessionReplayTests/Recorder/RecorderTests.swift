/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

private class RUMContextObserverMock: RUMContextObserver {
    private var queue: Queue?
    private var onNew: ((RUMContext?) -> Void)?

    func observe(on queue: Queue, notify: @escaping (RUMContext?) -> Void) {
        self.queue = queue
        self.onNew = notify
    }

    func notify(rumContext: RUMContext?) {
        queue?.run { self.onNew?(rumContext) }
    }
}

class RecorderTests: XCTestCase {
    func testGivenRUMContextAvailable_whenStarted_itCapturesSnapshotsAndPassesThemToProcessor() {
        let numberOfSnapshots = 10
        let mockSnapshots: [ViewTreeSnapshot] = .mockRandom(count: numberOfSnapshots)
        let rumContextObserver = RUMContextObserverMock()
        let processor = ProcessorSpy()

        // Given
        let recorder = Recorder(
            configuration: .mockAny(),
            rumContextObserver: rumContextObserver,
            scheduler: TestScheduler(numberOfRepeats: numberOfSnapshots),
            snapshotProducer: SnapshotProducerMock(succeedingSnapshots: mockSnapshots),
            snapshotProcessor: processor
        )
        rumContextObserver.notify(rumContext: .mockAny())

        // When
        recorder.start()

        // Then
        XCTAssertEqual(processor.processedSnapshots.count, numberOfSnapshots, "Processor should receive \(numberOfSnapshots) snapshots")
        XCTAssertEqual(processor.processedSnapshots, mockSnapshots)
    }

    func testGivenNoRUMContextAvailable_whenStarted_itDoesNotCaptureAnySnapshots() {
        let rumContextObserver = RUMContextObserverMock()
        let processor = ProcessorSpy()

        // Given
        let recorder = Recorder(
            configuration: .mockAny(),
            rumContextObserver: rumContextObserver,
            scheduler: TestScheduler(numberOfRepeats: 1),
            snapshotProducer: SnapshotProducerMock(succeedingSnapshots: .mockAny(count: 1)),
            snapshotProcessor: processor
        )
        rumContextObserver.notify(rumContext: nil)

        // When
        recorder.start()

        // Then
        XCTAssertTrue(processor.processedSnapshots.isEmpty)
    }

    func testGivenRUMContextAvailable_whenCapturingSnapshot_itUsesDefaultRecorderContext() {
        let randomPrivacy: SessionReplayPrivacy = .mockRandom()
        let randomRUMContext: RUMContext = .mockRandom()
        let rumContextObserver = RUMContextObserverMock()
        let snapshotProducer = SnapshotProducerSpy()

        // Given
        let recorder = Recorder(
            configuration: SessionReplayConfiguration(privacy: randomPrivacy),
            rumContextObserver: rumContextObserver,
            scheduler: TestScheduler(numberOfRepeats: 1),
            snapshotProducer: snapshotProducer,
            snapshotProcessor: ProcessorSpy()
        )
        rumContextObserver.notify(rumContext: randomRUMContext)

        // When
        recorder.start()

        // Then
        XCTAssertEqual(snapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(snapshotProducer.succeedingContexts[0].privacy, randomPrivacy)
        XCTAssertEqual(snapshotProducer.succeedingContexts[0].rumContext, randomRUMContext)
    }

    func testGivenRUMContextAvailable_whenCapturingSnapshot_itUsesCurrentRecorderContext() {
        let rumContextObserver = RUMContextObserverMock()
        let snapshotProducer = SnapshotProducerSpy()

        // Given
        let recorder = Recorder(
            configuration: SessionReplayConfiguration(privacy: .mockRandom()),
            rumContextObserver: rumContextObserver,
            scheduler: TestScheduler(numberOfRepeats: 1),
            snapshotProducer: snapshotProducer,
            snapshotProcessor: ProcessorSpy()
        )
        rumContextObserver.notify(rumContext: .mockRandom())

        // When
        let currentPrivacy: SessionReplayPrivacy = .mockRandom()
        recorder.change(privacy: currentPrivacy)

        let currentRUMContext: RUMContext = .mockRandom()
        rumContextObserver.notify(rumContext: currentRUMContext)

        recorder.start()

        // Then
        XCTAssertEqual(snapshotProducer.succeedingContexts.count, 1)
        XCTAssertEqual(snapshotProducer.succeedingContexts[0].privacy, currentPrivacy)
        XCTAssertEqual(snapshotProducer.succeedingContexts[0].rumContext, currentRUMContext)
    }
}
