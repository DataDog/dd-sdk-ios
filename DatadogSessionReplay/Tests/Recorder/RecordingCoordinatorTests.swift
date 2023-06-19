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
    private var core = PassthroughCoreMock()
    private var scheduler = TestScheduler()
    private var rumContextObserver = RUMContextObserverMock()
    private lazy var srContextPublisher: SRContextPublisher = {
        SRContextPublisher(core: core)
    }()
    private var sut: RecordingCoordinator?

    func test_itStartsScheduler_afterInitializing() {
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        XCTAssertTrue(scheduler.isRunning)
    }

    func test_whenSampled_itStartsScheduler_andDoesSetRecordingIsPending() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, true)
        XCTAssertEqual(sut?.currentRUMContext, rumContext)
        XCTAssertEqual(sut?.isSampled, true)
    }

    func test_whenNoRUMContext_itDoesNotSetRecordingIsPending() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(core.context.featuresAttributes["session-replay"]?.attributes["has_replay"] as? Bool, false)
        XCTAssertNil(sut?.currentRUMContext)
    }

    private func prepareRecordingCoordinator(sampler: Sampler) {
        sut = RecordingCoordinator(
            scheduler: scheduler,
            rumContextObserver: rumContextObserver,
            srContextPublisher: srContextPublisher,
            sampler: sampler
        )
    }
}
