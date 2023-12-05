/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

class RecordingCoordinatorTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    var recordingCoordinator: RecordingCoordinator?

    private var recordingMock = RecordingMock()
    private var scheduler = TestScheduler()
    private var rumContextObserver = RUMContextObserverMock()
    private lazy var contextPublisher: SRContextPublisher = {
        SRContextPublisher(core: core)
    }()

    override func setUpWithError() throws {
        core = PassthroughCoreMock()
    }

    override func tearDown() {
        core = nil
        XCTAssertEqual(PassthroughCoreMock.referenceCount, 0)
    }

    func test_itStartsScheduler_afterInitializing() {
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenNotSampled_itStopsScheduler_andShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 0))

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenSampled_itStartsScheduler_andShouldRecord() {
        // Given
        let privacy = PrivacyLevel.mockRandom()
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100), privacy: privacy)

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.applicationID, rumContext.applicationID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.sessionID, rumContext.sessionID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewID, rumContext.viewID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewServerTimeOffset, rumContext.viewServerTimeOffset)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.privacy, privacy)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenEmptyRUMContext_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // When
        rumContextObserver.notify(rumContext: nil)

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenNoRUMContext_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenRUMContextWithoutViewID_itStartsScheduler_andShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: 100))

        // When
        let rumContext = RUMContext.mockWith(viewID: nil)
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    private func prepareRecordingCoordinator(sampler: Sampler, privacy: PrivacyLevel = .allow) {
        recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            privacy: privacy,
            rumContextObserver: rumContextObserver,
            srContextPublisher: contextPublisher,
            recorder: recordingMock,
            sampler: sampler
        )
    }
}

final class RecordingMock: Recording {
   // MARK: - captureNextRecord

    var captureNextRecordCallsCount = 0
    var captureNextRecordCalled: Bool {
        captureNextRecordCallsCount > 0
    }
    var captureNextRecordReceivedRecorderContext: Recorder.Context?
    var captureNextRecordReceivedInvocations: [Recorder.Context] = []
    var captureNextRecordClosure: ((Recorder.Context) -> Void)?

    func captureNextRecord(_ recorderContext: Recorder.Context) {
        captureNextRecordCallsCount += 1
        captureNextRecordReceivedRecorderContext = recorderContext
        captureNextRecordReceivedInvocations.append(recorderContext)
        captureNextRecordClosure?(recorderContext)
    }
}
