/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

class RecordingCoordinatorTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    var recordingCoordinator: RecordingCoordinator?

    private var recordingMock = RecordingMock()
    private var rumContextObserver = RUMContextObserverMock()
    private var dateProviderMock = RelativeDateProvider()
    private var recordingTriggerMock = RecordingTriggerMock()
    private lazy var contextPublisher: SRContextPublisher = {
        SRContextPublisher(core: core)
    }()
    private let queue = NoQueue()

    override func setUpWithError() throws {
        core = PassthroughCoreMock()
    }

    override func tearDown() {
        core = nil
        XCTAssertEqual(PassthroughCoreMock.referenceCount, 0)
    }

    // MARK: Configuration Tests

    func test_itDoesNotStart_afterInitializing() {
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))
        recordingCoordinator?.startRecording()

        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 1)
    }

    func test_whenNotSampledAndTriggered_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: .mockRejectAll())
        recordingCoordinator?.startRecording()

        // When
        rumContextObserver.notify(rumContext: .mockRandom())
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 2)
    }

    func test_whenSampledAndTriggered_itShouldRecord() {
        // Given
        let textAndInputPrivacy = TextAndInputPrivacyLevel.mockRandom()
        let imagePrivacy = ImagePrivacyLevel.mockRandom()
        let touchPrivacy = TouchPrivacyLevel.mockRandom()
        prepareRecordingCoordinator(textAndInputPrivacy: textAndInputPrivacy, imagePrivacy: imagePrivacy, touchPrivacy: touchPrivacy)
        recordingCoordinator?.startRecording()

        // When
        recordingCoordinator?.startRecording()
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.applicationID, rumContext.applicationID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.sessionID, rumContext.sessionID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewID, rumContext.viewID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewServerTimeOffset, rumContext.viewServerTimeOffset)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.imagePrivacy, imagePrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.touchPrivacy, touchPrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 2)
    }

    func test_whenEmptyRUMContextAndTriggered_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: .mockKeepAll())
        recordingCoordinator?.startRecording()

        // When
        rumContextObserver.notify(rumContext: nil)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 1)
    }

    func test_whenNoRUMContextAndTriggered_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(sampler: Sampler(samplingRate: .mockRandom(min: 0, max: 100)))
        recordingCoordinator?.startRecording()
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 1)
    }

    func test_whenRUMContextWithoutViewIDAndTriggered_itShouldRecord_itShouldNotCaptureSnapshots() {
        // Given
        prepareRecordingCoordinator()
        recordingCoordinator?.startRecording()

        // When
        let rumContext = RUMContext.mockWith(viewID: nil)
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 1)
    }

    // MARK: Telemetry Tests

    func test_whenCapturingSnapshotFails_itSendsErrorTelemetry() {
        let telemetry = TelemetryMock()

        // Given
        recordingMock.captureNextRecordClosure = { _ in
            throw ErrorMock("snapshot creation error")
        }

        prepareRecordingCoordinator(telemetry: telemetry)
        recordingCoordinator?.startRecording()

        // When
        rumContextObserver.notify(rumContext: .mockRandom())
        recordingTriggerMock.triggerCallback?()

        // Then
        let error = telemetry.messages.firstError()
        XCTAssertEqual(error?.message, "[SR] Failed to take snapshot - snapshot creation error")
        XCTAssertEqual(error?.kind, "ErrorMock")
        XCTAssertEqual(error?.stack, "snapshot creation error")
    }

    func test_whenCapturingSnapshotFails_withObjCRuntimeException_itSendsErrorTelemetry() {
        let telemetry = TelemetryMock()

        // Given
        recordingMock.captureNextRecordClosure = { _ in
            throw ObjcException(error: ErrorMock("snapshot creation error"), file: "File.swift", line: 0)
        }

        prepareRecordingCoordinator(telemetry: telemetry)
        recordingCoordinator?.startRecording()

        // When
        rumContextObserver.notify(rumContext: .mockRandom())
        recordingTriggerMock.triggerCallback?()

        // Then
        let error = telemetry.messages.firstError()
        XCTAssertEqual(error?.message, "[SR] Failed to take snapshot due to Objective-C runtime exception - snapshot creation error")
        XCTAssertEqual(error?.kind, "ErrorMock")
        XCTAssertEqual(error?.stack, "snapshot creation error")
    }

    // MARK: startRecording Tests

    func test_whenStartRecordingImmediatelyIsDefault_itShouldRecord() throws {
        // Given
        prepareRecordingCoordinator()
        recordingCoordinator?.startRecording()

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenStartRecordingImmediatelyIsTrue_itShouldRecord() throws {
        // Given
        prepareRecordingCoordinator()
        recordingCoordinator?.startRecording()

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenStartRecordingImmediatelyIsFalse_shouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator()

        // When
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenCapturingSnapshot_itSendsMethodCalledTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()
        prepareRecordingCoordinator(
            telemetry: telemetry,
            methodCallTelemetrySamplingRate: 100
        )

        // When
        recordingCoordinator?.startRecording()
        rumContextObserver.notify(rumContext: .mockRandom())
        recordingTriggerMock.triggerCallback?()

        // Then
        let metric = try XCTUnwrap(telemetry.messages.last?.asMetric)
        XCTAssertEqual(metric.name, "Method Called")
    }

    // MARK: Start / Stop API Tests

    func test_whenStopRecording_shouldStopRecord() throws {
        // Given
        prepareRecordingCoordinator()

        // When
        recordingCoordinator?.startRecording()
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingTriggerMock.triggerCallback?()

        recordingCoordinator?.stopRecording()
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 2)
    }

    func test_startRecording_whenAlreadyRecording_shouldRecord() throws {
        // Given
        prepareRecordingCoordinator()
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingCoordinator?.startRecording()

        // When
        recordingTriggerMock.triggerCallback?()
        recordingCoordinator?.startRecording()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), true)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 2)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 1)
    }

    func test_stopRecording_whenAlreadyStopped_shouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator()
        recordingCoordinator?.startRecording()

        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingCoordinator?.stopRecording()

        // When
        recordingTriggerMock.triggerCallback?()
        recordingCoordinator?.stopRecording()

        // Then
        XCTAssertEqual(try core.context.baggages["sr_has_replay"]?.decode(), false)
        XCTAssertEqual(recordingTriggerMock.startWatchingTriggersCallsCount, 1)
        XCTAssertEqual(recordingTriggerMock.stopWatchingTriggersCallsCount, 3)
    }

    func test_snapshotIsSkippedWhenHappensBeforeThrottling() {
        // Given
        prepareRecordingCoordinator()
        let rumContext = RUMContext.mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingCoordinator?.startRecording()

        // When
        recordingTriggerMock.triggerCallback?()
        dateProviderMock.advance(bySeconds: 0.01) // 10ms
        recordingTriggerMock.triggerCallback?()
        dateProviderMock.advance(bySeconds: 0.1) // 100ms
        recordingTriggerMock.triggerCallback?()

        // Then
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 2)
    }

    private func prepareRecordingCoordinator(
        sampler: Sampler = .mockKeepAll(),
        textAndInputPrivacy: TextAndInputPrivacyLevel = .maskSensitiveInputs,
        imagePrivacy: ImagePrivacyLevel = .maskNonBundledOnly,
        touchPrivacy: TouchPrivacyLevel = .show,
        telemetry: Telemetry = NOPTelemetry(),
        methodCallTelemetrySamplingRate: Float = 0
    ) {
        recordingCoordinator = try? RecordingCoordinator(
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            rumContextObserver: rumContextObserver,
            srContextPublisher: contextPublisher,
            recorder: recordingMock,
            sampler: sampler,
            telemetry: telemetry,
            recordingTrigger: recordingTriggerMock,
            methodCallTelemetrySamplingRate: methodCallTelemetrySamplingRate,
            dateProvider: dateProviderMock,
            queue: queue
        )
    }
}

final class RecordingTriggerMock: RecordingTriggering {
    var triggerCallback: (() -> Void)?
    var startWatchingTriggersCallsCount = 0
    func startWatchingTriggers(_ callback: @escaping () -> Void) {
        triggerCallback = callback
        startWatchingTriggersCallsCount += 1
    }

    var stopWatchingTriggersCallsCount = 0
    func stopWatchingTriggers() {
        stopWatchingTriggersCallsCount += 1
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
    var captureNextRecordClosure: ((Recorder.Context) throws -> Void)?

    func captureNextRecord(_ recorderContext: Recorder.Context) throws {
        captureNextRecordCallsCount += 1
        captureNextRecordReceivedRecorderContext = recorderContext
        captureNextRecordReceivedInvocations.append(recorderContext)
        try captureNextRecordClosure?(recorderContext)
    }
}
#endif
