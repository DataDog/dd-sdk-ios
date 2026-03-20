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

    // MARK: Configuration Tests

    func test_itDoesNotStartScheduler_afterInitializing() {
        prepareRecordingCoordinator(replaySampleRate: .mockRandom(min: 0, max: 100))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenNotSampled_itStopsScheduler_andShouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator(replaySampleRate: 0.0)

        // When
        rumContextObserver.notify(rumContext: .mockRandom())

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenSampled_itStartsScheduler_andShouldRecord() throws {
        // Given
        let textAndInputPrivacy = TextAndInputPrivacyLevel.mockRandom()
        let imagePrivacy = ImagePrivacyLevel.mockRandom()
        let touchPrivacy = TouchPrivacyLevel.mockRandom()
        prepareRecordingCoordinator(textAndInputPrivacy: textAndInputPrivacy, imagePrivacy: imagePrivacy, touchPrivacy: touchPrivacy)

        // When
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.applicationID, rumContext.applicationID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.sessionID, rumContext.sessionID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewID, rumContext.viewID)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.viewServerTimeOffset, rumContext.viewServerTimeOffset)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.imagePrivacy, imagePrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordReceivedRecorderContext?.touchPrivacy, touchPrivacy)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenEmptyRUMContext_itShouldNotRecord() {
        // Given
        prepareRecordingCoordinator(replaySampleRate: .mockRandom(min: 0, max: 100))

        // When
        rumContextObserver.notify(rumContext: nil)

        // Then
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenNoRUMContext_itShouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator(replaySampleRate: .mockRandom(min: 0, max: 100))

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    func test_whenRUMContextWithoutViewID_itShouldRecord_itShouldNotCaptureSnapshots() throws {
        // Given
        prepareRecordingCoordinator()

        // When
        let rumContext: RUMCoreContext = .mockWith(viewID: nil)
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    // MARK: Telemetry Tests

    func test_whenCapturingSnapshotFails_itSendsErrorTelemetry() {
        let telemetry = TelemetryMock()

        // Given
        recordingMock.captureNextRecordClosure = { _ in
            throw ErrorMock("snapshot creation error")
        }

        prepareRecordingCoordinator(telemetry: telemetry)

        // When
        rumContextObserver.notify(rumContext: .mockRandom())

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

        // When
        rumContextObserver.notify(rumContext: .mockRandom())

        // Then
        let error = telemetry.messages.firstError()
        XCTAssertEqual(error?.message, "[SR] Failed to take snapshot due to Objective-C runtime exception - snapshot creation error")
        XCTAssertEqual(error?.kind, "ErrorMock")
        XCTAssertEqual(error?.stack, "snapshot creation error")
        XCTAssertFalse(scheduler.isRunning)
    }

    func test_whenCapturingSnapshot_itSendsMethodCalledTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()
        prepareRecordingCoordinator(
            telemetry: telemetry,
            methodCallTelemetrySamplingRate: 100
        )

        // When
        rumContextObserver.notify(rumContext: .mockRandom())

        // Then
        let metric = try XCTUnwrap(telemetry.messages.last?.asMetric)
        XCTAssertEqual(metric.name, "Method Called")
    }

    func test_whenCaptureReenters_itSkipsNestedCapture() {
        // Given
        var didTriggerReentry = false
        recordingMock.captureNextRecordClosure = { _ in
            guard !didTriggerReentry else {
                return
            }

            didTriggerReentry = true
            self.scheduler.start()
        }
        prepareRecordingCoordinator()

        // When
        rumContextObserver.notify(rumContext: .mockRandom())

        // Then
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    // MARK: StartRecordingImmediately Initialization Tests

    func test_whenStartRecordingImmediatelyIsDefault_itShouldRecord() throws {
        // Given
        prepareRecordingCoordinator()

        // When
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenStartRecordingImmediatelyIsTrue_itShouldRecord() throws {
        // Given
        prepareRecordingCoordinator(startRecordingImmediately: true)

        // When
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 1)
    }

    func test_whenStartRecordingImmediatelyIsFalse_shouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator(startRecordingImmediately: false)

        // When
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(hasReplay.value)
        XCTAssertEqual(recordingMock.captureNextRecordCallsCount, 0)
    }

    // MARK: Start / Stop API Tests

    func test_whenStopRecording_shouldStopRecord() throws {
        // Given
        prepareRecordingCoordinator()
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)

        // When
        recordingCoordinator?.stopRecording()

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(hasReplay.value)
    }

    func test_startRecording_whenAlreadyRecording_shouldRecord() throws {
        // Given
        prepareRecordingCoordinator()
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingCoordinator?.startRecording()

        // When
        recordingCoordinator?.startRecording()

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hasReplay.value)
    }

    func test_stopRecording_whenAlreadyStopped_shouldNotRecord() throws {
        // Given
        prepareRecordingCoordinator()
        let rumContext: RUMCoreContext = .mockRandom()
        rumContextObserver.notify(rumContext: rumContext)
        recordingCoordinator?.stopRecording()

        // When
        recordingCoordinator?.stopRecording()

        // Then
        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertFalse(hasReplay.value)
    }

    // MARK: - Deterministic sampling

    func test_givenSameSessionID_samplingDecisionIsIdentical_acrossMultipleCalls() {
        // Given
        prepareRecordingCoordinator(replaySampleRate: 60.0)
        let fixedSessionID = "abcdef01-2345-6789-abcd-ef0123456789"
        let sessionSampler = DeterministicSampler(uuid: .mockWith(fixedSessionID), samplingRate: 70.0)
        let rumContext = RUMCoreContext(
            applicationID: "app-id",
            sessionID: fixedSessionID,
            sessionSampler: sessionSampler,
            viewID: "view-id"
        )

        // When
        rumContextObserver.notify(rumContext: rumContext)
        let firstDecision = scheduler.isRunning

        rumContextObserver.notify(rumContext: rumContext)
        let secondDecision = scheduler.isRunning

        // Then
        XCTAssertEqual(firstDecision, secondDecision, "Knuth sampling must be deterministic for the same session UUID")
    }

    func test_knownSessionUUID_matchesPrecomputedKnuthResult() throws {
        // UUID: "abcdef01-2345-6789-abcd-ef0123456789", last segment 0xef0123456789
        // sessionRate=50, replayRate=80 → effectiveRate=40.0
        let knownSessionID = "abcdef01-2345-6789-abcd-ef0123456789"
        let replaySampleRate: SampleRate = 80.0
        let sessionSampleRate: SampleRate = 50.0

        // Precompute using combined(with:) — canonical cross-SDK formula
        let sessionSampler = DeterministicSampler(uuid: .mockWith(knownSessionID), samplingRate: sessionSampleRate)
        let expectedResult = sessionSampler.combined(with: replaySampleRate).isSampled

        prepareRecordingCoordinator(replaySampleRate: replaySampleRate)
        let rumContext = RUMCoreContext(
            applicationID: "app-id",
            sessionID: knownSessionID,
            sessionSampler: sessionSampler,
            viewID: "view-id"
        )
        rumContextObserver.notify(rumContext: rumContext)

        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertEqual(
            scheduler.isRunning,
            expectedResult,
            "RecordingCoordinator must use sessionSampler.combined(with:).isSampled with the composed effective rate"
        )
        XCTAssertEqual(hasReplay.value, expectedResult)
    }

    func test_childRateCorrectionIsApplied_replay() throws {
        // seed 0xd860b2b9437a (~68.7% hash): sampled at replay-only 80% but NOT at composed 40% (50*80/100)
        // This verifies the session rate is not ignored.
        let knownSessionID = "00000000-0000-0000-0000-d860b2b9437a"
        let sessionSampleRate: SampleRate = 50.0
        let replaySampleRate: SampleRate = 80.0

        let sessionSampler = DeterministicSampler(uuid: .mockWith(knownSessionID), samplingRate: sessionSampleRate)
        let composedResult = sessionSampler.combined(with: replaySampleRate).isSampled
        let replayOnlyResult = DeterministicSampler(uuid: .mockWith(knownSessionID), samplingRate: replaySampleRate).isSampled
        guard composedResult != replayOnlyResult else {
            XCTFail("Precondition: chosen vector must differ between composed and replay-only rate")
            return
        }

        prepareRecordingCoordinator(replaySampleRate: replaySampleRate)
        let rumContext = RUMCoreContext(
            applicationID: "app",
            sessionID: knownSessionID,
            sessionSampler: sessionSampler,
            viewID: "view"
        )
        rumContextObserver.notify(rumContext: rumContext)

        let hasReplay = try XCTUnwrap(core.context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self))
        XCTAssertEqual(
            scheduler.isRunning,
            composedResult,
            "RecordingCoordinator must apply child-rate correction via sessionSampler.combined(with:)"
        )
        XCTAssertEqual(hasReplay.value, composedResult)
    }

    private func prepareRecordingCoordinator(
        replaySampleRate: SampleRate = 100.0,
        textAndInputPrivacy: TextAndInputPrivacyLevel = .maskSensitiveInputs,
        imagePrivacy: ImagePrivacyLevel = .maskNonBundledOnly,
        touchPrivacy: TouchPrivacyLevel = .show,
        telemetry: Telemetry = NOPTelemetry(),
        methodCallTelemetrySamplingRate: Float = 0,
        startRecordingImmediately: Bool = true
    ) {
        recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            rumContextObserver: rumContextObserver,
            srContextPublisher: contextPublisher,
            recorder: recordingMock,
            replaySampleRate: replaySampleRate,
            telemetry: telemetry,
            startRecordingImmediately: startRecordingImmediately,
            methodCallTelemetrySamplingRate: methodCallTelemetrySamplingRate
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
    var captureNextRecordClosure: ((Recorder.Context) throws -> Void)?

    func captureNextRecord(_ recorderContext: Recorder.Context) throws {
        captureNextRecordCallsCount += 1
        captureNextRecordReceivedRecorderContext = recorderContext
        captureNextRecordReceivedInvocations.append(recorderContext)
        try captureNextRecordClosure?(recorderContext)
    }
}
#endif
