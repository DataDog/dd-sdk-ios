/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// managing the recording state, starting/stopping the recording scheduler as needed,
/// and propagating `has_replay` to other features.

internal class RecordingCoordinator {
    let recorder: Recording
    let scheduler: Scheduler
    let sampler: Sampler
    let textAndInputPrivacy: TextAndInputPrivacyLevel
    let imagePrivacy: ImagePrivacyLevel
    let touchPrivacy: TouchPrivacyLevel
    let srContextPublisher: SRContextPublisher

    private var currentRUMContext: RUMContext? = nil
    private var isSampled = false

    /// `recordingEnabled` is used to track when the user 
    /// has enabled or disabled the recording for Session Replay.
    private var recordingEnabled = false

    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry
    /// The sampling rate for internal telemetry of method calls.
    private let methodCallTelemetrySamplingRate: Float

    init(
        scheduler: Scheduler,
        textAndInputPrivacy: TextAndInputPrivacyLevel,
        imagePrivacy: ImagePrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        recorder: Recording,
        sampler: Sampler,
        telemetry: Telemetry,
        startRecordingImmediately: Bool,
        methodCallTelemetrySamplingRate: Float = 0.1
    ) {
        self.recorder = recorder
        self.scheduler = scheduler
        self.sampler = sampler
        self.textAndInputPrivacy = textAndInputPrivacy
        self.imagePrivacy = imagePrivacy
        self.touchPrivacy = touchPrivacy
        self.srContextPublisher = srContextPublisher
        self.telemetry = telemetry
        self.methodCallTelemetrySamplingRate = methodCallTelemetrySamplingRate

        srContextPublisher.setHasReplay(false)

        scheduler.schedule { [weak self] in self?.captureNextRecord() }

        // Start recording immediately if specified.
        if startRecordingImmediately {
            startRecording()
        }

        // Observe changes in the RUM context.
        rumContextObserver.observe(on: scheduler.queue) { [weak self] in self?.onRUMContextChanged(rumContext: $0) }
    }

    /// Enables recording based on user request.
    func startRecording() {
        scheduler.queue.run { [weak self] in
            self?.recordingEnabled = true
            self?.evaluateRecordingConditions()
        }
    }

    /// Disables recording based on user request.
    func stopRecording() {
        scheduler.queue.run { [weak self] in
            self?.recordingEnabled = false
            self?.evaluateRecordingConditions()
        }
    }

    // MARK: Private

    /// Evaluates whether recording should start or stop based on user request and sampling.
    private func evaluateRecordingConditions() {
       if recordingEnabled && isSampled {
           scheduler.start()
       } else {
           scheduler.stop()
       }
       updateHasReplay()
   }

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

    /// Captures the next recording if conditions are met.
    private func captureNextRecord() {
        /// We don't capture any snapshots if the RUM context has no view ID.
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
            viewServerTimeOffset: rumContext.viewServerTimeOffset,
            date: Date(),
            telemetry: telemetry
        )

        let methodCalledTrace = telemetry.startMethodCalled(
            operationName: MethodCallConstants.captureRecordOperationName,
            callerClass: MethodCallConstants.className,
            headSampleRate: methodCallTelemetrySamplingRate // Effectively 3% * 0.1% = 0.003% of calls
        )

        var isSuccessful = false
        do {
            try objc_rethrow { try recorder.captureNextRecord(recorderContext) }
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

    private enum MethodCallConstants {
        static let captureRecordOperationName = "Capture Record"
        static let className = "Recorder"
    }
}
#endif
