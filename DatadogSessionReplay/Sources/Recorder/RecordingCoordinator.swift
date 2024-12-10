/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// managing the recording state, starting/stopping the recording,
/// and propagating `has_replay` to other features.
///
/// The `RecordingCoordinator` is responsible for orchestrating the process of capturing
/// snapshots on the main thread.
///
/// Subsequent requests to capture snapshots are throttled to avoid performance issues.
internal class RecordingCoordinator {
    let recorder: Recording
    let sampler: Sampler
    let textAndInputPrivacy: TextAndInputPrivacyLevel
    let imagePrivacy: ImagePrivacyLevel
    let touchPrivacy: TouchPrivacyLevel
    let srContextPublisher: SRContextPublisher

    private var currentRUMContext: RUMContext? = nil
    private var isSampled: Bool = false

    /// `recordingEnabled` is used to track when the user
    /// has enabled or disabled the recording for Session Replay.
    private var recordingEnabled = false

    private var isRecording = false

    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry
    /// The sampling rate for internal telemetry of method calls.
    private let methodCallTelemetrySamplingRate: Float

    private let dateProvider: DateProvider

    private var recordingTrigger: RecordingTriggering

    private let queue: Queue

    init(
        textAndInputPrivacy: TextAndInputPrivacyLevel,
        imagePrivacy: ImagePrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        recorder: Recording,
        sampler: Sampler,
        telemetry: Telemetry,
        recordingTrigger: RecordingTriggering,
        methodCallTelemetrySamplingRate: Float = 0.1,
        dateProvider: DateProvider = SystemDateProvider(),
        queue: Queue = MainAsyncQueue()
    ) throws {
        self.recorder = recorder
        self.sampler = sampler
        self.textAndInputPrivacy = textAndInputPrivacy
        self.imagePrivacy = imagePrivacy
        self.touchPrivacy = touchPrivacy
        self.srContextPublisher = srContextPublisher
        self.telemetry = telemetry
        self.recordingTrigger = recordingTrigger
        self.methodCallTelemetrySamplingRate = methodCallTelemetrySamplingRate
        self.dateProvider = dateProvider
        self.queue = queue

        srContextPublisher.setHasReplay(false)

        // Observe changes in the RUM context on the main thread.
        rumContextObserver.observe(on: queue) { [weak self] in
            self?.onRUMContextChanged(rumContext: $0)
        }
    }

    /// Enables recording based on user request.
    func startRecording() {
        queue.run { [weak self] in
            self?.recordingEnabled = true
            self?.evaluateRecordingConditions()
        }
    }

    /// Disables recording based on user request.
    func stopRecording() {
        queue.run { [weak self] in
            self?.recordingEnabled = false
            self?.evaluateRecordingConditions()
        }
    }

    private func evaluateRecordingConditions() {
        if !isRecording && recordingEnabled && isSampled && currentRUMContext != nil {
            isRecording = true
            recordingTrigger.startWatchingTriggers { [weak self] in
                self?.didTrigger()
            }
            updateHasReplay()
        } else if isRecording && (!recordingEnabled || !isSampled) {
            isRecording = false
            recordingTrigger.stopWatchingTriggers()
            updateHasReplay()
        }
    }

    // MARK: Private

    private func onRUMContextChanged(rumContext: RUMContext?) {
        if currentRUMContext?.sessionID != rumContext?.sessionID || currentRUMContext == nil {
            isSampled = sampler.sample()
        }

        currentRUMContext = rumContext

        evaluateRecordingConditions()
    }

    /// Updates the `has_replay` flag to indicate if recording is active.
    private func updateHasReplay() {
        /// `has_replay` is set to `true` only when the session is sampled
        /// and  the user has enabled the recording.
        let hasReplay = isSampled == true && recordingEnabled == true
        srContextPublisher.setHasReplay(hasReplay)
    }

    private var lastTriggerDate: Date?

    private var shouldSkipTrigger: Bool {
        return dateProvider.now.timeIntervalSince(lastTriggerDate ?? .distantPast) < Constants.throttlingRate
    }

    private func didTrigger() {
        guard shouldSkipTrigger == false else {
            return
        }
        lastTriggerDate = dateProvider.now
        captureNextRecord()
    }

    private func captureNextRecord() {
        // We don't capture any snapshots if the RUM context has no view ID.
        guard let rumContext = currentRUMContext,
              let viewID = rumContext.viewID else {
            return
        }

        let recorderContext = Recorder.Context(
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            applicationID: rumContext.applicationID,
            sessionID: rumContext.sessionID,
            viewID: viewID,
            viewServerTimeOffset: rumContext.viewServerTimeOffset
        )

        let methodCalledTrace = telemetry.startMethodCalled(
            operationName: MethodCallConstants.captureRecordOperationName,
            callerClass: MethodCallConstants.className,
            headSampleRate: methodCallTelemetrySamplingRate // Effectively 3% * 0.1% = 0.003% of calls
        )

        var isSuccessful = false
        do {
            try objc_rethrow { [weak self] in
                try self?.recorder.captureNextRecord(recorderContext)
            }
            isSuccessful = true
        } catch let objc as ObjcException {
            telemetry.error("[SR] Failed to take snapshot due to Objective-C runtime exception", error: objc.error)
            // An Objective-C runtime exception is a severe issue that will leak if
            // the framework is not built with `-fobjc-arc-exceptions` option.
            // We recover from the exception and stop the scheduler as a measure of
            // caution. The scheduler could start again at a next RUM context change.
            stopRecording()
        } catch {
            telemetry.error("[SR] Failed to take snapshot", error: error)
        }

        telemetry.stopMethodCalled(methodCalledTrace, isSuccessful: isSuccessful)
    }

    private enum Constants {
        static let throttlingRate: TimeInterval = 0.1 // 100ms
    }

    private enum MethodCallConstants {
        static let captureRecordOperationName = "Capture Record"
        static let className = "Recorder"
    }
}
#endif
