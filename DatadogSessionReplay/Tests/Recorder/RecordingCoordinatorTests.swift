/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

import Datadog

class RecordingCoordinatorTests: XCTestCase {

    private var scheduler: TestScheduler!
    private var rumContextObserver: RUMContextObserverMock!
    private var contextPublisher: SRContextPublisher!
    private var core = PassthroughCoreMock()
    private var sut: RecordingCoordinator!

    override func setUp() {
        scheduler = TestScheduler()
        rumContextObserver = RUMContextObserverMock()
        contextPublisher = SRContextPublisher(core: core)
    }

    func test_whenNotSampled_itStopsScheduler_andDoesNotSetRecordingIsPending() {
        // Given
        scheduler.start()
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 0))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertEqual(scheduler.isRunning, false)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertEqual(sut.currentRUMContext, rumContext)
    }

    func test_whenSampled_itStartsScheduler_andDoesSetRecordingIsPending() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertEqual(scheduler.isRunning, true)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, true)
        XCTAssertEqual(sut.currentRUMContext, rumContext)
    }

    func test_whenEmptyRUMContext_itStopsScheduler_andDoesNotSetRecordingIsPending() {
        // Given
        scheduler.start()
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // When
        rumContextObserver.notify(rumContext: nil)

        // Then
        XCTAssertEqual(scheduler.isRunning, false)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNil(sut.currentRUMContext)
    }

    func test_whenNoRUMContext_itDoesNotSetRecordingIsPending() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // Then
        XCTAssertEqual(scheduler.isRunning, false)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNil(sut.currentRUMContext)
    }

    private func prepareRecordingCoordinator(sampler: Sampler) {
        sut = RecordingCoordinator(
            scheduler: scheduler,
            rumContextObserver: rumContextObserver,
            contextPublisher: contextPublisher,
            sampler: sampler
        )
    }
}
