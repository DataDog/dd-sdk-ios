/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Object is responsible for getting the RUM context, randomising the sampling rate,
/// starting/stopping the recording scheduler as needed and propagating `has_replay` to other features.
internal class RecordingCoordinator {
    let recorder: Recording
    let scheduler: Scheduler
    let sampler: Sampler
    let privacy: PrivacyLevel
    let touchPrivacy: TouchPrivacyLevel
    let srContextPublisher: SRContextPublisher

    private var currentRUMContext: RUMContext? = nil
    private var isSampled = false

    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry
    /// The sampling rate for internal telemetry of method call.
    private let methodCallTelemetrySamplingRate: Float

    init(
        scheduler: Scheduler,
        privacy: PrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        rumContextObserver: RUMContextObserver,
        srContextPublisher: SRContextPublisher,
        recorder: Recording,
        sampler: Sampler,
        telemetry: Telemetry,
        methodCallTelemetrySamplingRate: Float = 0.1
    ) {
        self.recorder = recorder
        self.scheduler = scheduler
        self.sampler = sampler
        self.privacy = privacy
        self.touchPrivacy = touchPrivacy
        self.srContextPublisher = srContextPublisher
        self.telemetry = telemetry
        self.methodCallTelemetrySamplingRate = methodCallTelemetrySamplingRate

        srContextPublisher.setHasReplay(false)

        scheduler.schedule { [weak self] in self?.captureNextRecord() }
        scheduler.start()

        rumContextObserver.observe(on: scheduler.queue) { [weak self] in self?.onRUMContextChanged(rumContext: $0) }
    }

    private func onRUMContextChanged(rumContext: RUMContext?) {
        if currentRUMContext?.sessionID != rumContext?.sessionID || currentRUMContext == nil {
            isSampled = sampler.sample()
        }

        currentRUMContext = rumContext

        if isSampled {
            scheduler.start()
        } else {
            scheduler.stop()
        }

        srContextPublisher.setHasReplay(
            isSampled == true && currentRUMContext?.viewID != nil
        )
    }

    private func captureNextRecord() {
        guard let rumContext = currentRUMContext,
              let viewID = rumContext.viewID else {
            return
        }

        let recorderContext = Recorder.Context(
            privacy: privacy,
            touchPrivacy: touchPrivacy,
            applicationID: rumContext.applicationID,
            sessionID: rumContext.sessionID,
            viewID: viewID,
            viewServerTimeOffset: rumContext.viewServerTimeOffset
        )

        let methodCalledTrace = telemetry.startMethodCalled(
            operationName: MethodCallConstants.captureRecordOperationName,
            callerClass: MethodCallConstants.className,
            samplingRate: methodCallTelemetrySamplingRate // Effectively 3% * 0.1% = 0.003% of calls
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
            scheduler.stop()
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
