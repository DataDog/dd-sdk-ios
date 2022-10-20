/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class RecorderTests: XCTestCase {
    func testWhenStarted_itCapturesSnapshotsAndPassesThemToProcessor() {
        let numberOfSnapshots = 10
        let mockSnapshots: [ViewTreeSnapshot] = .mockRandom(count: numberOfSnapshots)

        // Given
        let processor = ProcessorSpy()
        let recorder = Recorder(
            scheduler: TestScheduler(numberOfRepeats: numberOfSnapshots),
            snapshotProducer: SnapshotProducerMock(succeedingSnapshots: mockSnapshots),
            snapshotProcessor: processor
        )

        // When
        recorder.start()

        // Then
        XCTAssertEqual(processor.processedSnapshots.count, numberOfSnapshots, "Processor should receive \(numberOfSnapshots) snapshots")
        XCTAssertEqual(processor.processedSnapshots, mockSnapshots)
    }

    func testWhenCapturingSnapshot_itUsesPrivacyOption() {
        let randomPrivacy: SessionReplayPrivacy = .mockRandom()

        // Given
        let snapshotProducer = SnapshotProducerSpy()
        let recorder = Recorder(
            scheduler: TestScheduler(numberOfRepeats: 1),
            snapshotProducer: snapshotProducer,
            snapshotProcessor: ProcessorSpy()
        )

        // When
        recorder.privacy = randomPrivacy
        recorder.start()

        // Then
        XCTAssertEqual(snapshotProducer.succeedingOptions.count, 1)
        XCTAssertEqual(snapshotProducer.succeedingOptions[0].privacy, randomPrivacy)
    }
}
