/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

class RecordingCoordinatorTests: XCTestCase {
    var recordingCoordinator: RecordingCoordinator?

    private var core = PassthroughCoreMock()
    private var scheduler = TestScheduler()
    private var rumContextObserver = RUMContextObserverMock()
    private lazy var contextPublisher: SRContextPublisher = {
        SRContextPublisher(core: core)
    }()

    func test_itStartsScheduler_afterInitializing() {
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))
        XCTAssertTrue(scheduler.isRunning)
    }

    func test_whenNotSampled_itStopsScheduler_andShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 0))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertEqual(recordingCoordinator?.currentRUMContext, rumContext)
        XCTAssertEqual(recordingCoordinator?.shouldRecord, false)
    }

    func test_whenSampled_itStartsScheduler_andShouldRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, true)
        XCTAssertEqual(recordingCoordinator?.currentRUMContext, rumContext)
        XCTAssertEqual(recordingCoordinator?.shouldRecord, true)
    }

    func test_whenEmptyRUMContext_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // When
        rumContextObserver.notify(rumContext: nil)

        // Then
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNil(recordingCoordinator?.currentRUMContext)
        XCTAssertEqual(recordingCoordinator?.shouldRecord, false)
    }

    func test_whenNoRUMContext_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNil(recordingCoordinator?.currentRUMContext)
        XCTAssertEqual(recordingCoordinator?.shouldRecord, false)
    }

    func test_whenRUMContextWithoutViewID_itStartsScheduler_andShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100))

        // When
        rumContextObserver.notify(rumContext: .mockWith(viewID: nil))

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNotNil(recordingCoordinator?.currentRUMContext)
        XCTAssertEqual(recordingCoordinator?.shouldRecord, false)
    }

    private func prepareRecordingCoordinator(sampler: Sampler) {
        recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            rumContextObserver: rumContextObserver,
            srContextPublisher: contextPublisher,
            sampler: sampler
        )
    }
}
