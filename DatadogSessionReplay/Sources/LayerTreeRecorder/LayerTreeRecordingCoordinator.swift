/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@preconcurrency import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
internal final class LayerTreeRecordingCoordinator: RecordingController {
    let replaySampleRate: SampleRate
    let textAndInputPrivacy: TextAndInputPrivacyLevel
    let imagePrivacy: ImagePrivacyLevel
    let touchPrivacy: TouchPrivacyLevel

    private let screenChangeMonitor: ScreenChangeMonitor
    private let srContextPublisher: SRContextPublisher
    private let layerRecording: any LayerRecording
    private let telemetry: any Telemetry

    private var currentRUMContext: RUMCoreContext?
    private var isSampled = false
    private var recordingEnabled = false

    init(
        screenChangeMonitor: ScreenChangeMonitor,
        textAndInputPrivacy: TextAndInputPrivacyLevel,
        imagePrivacy: ImagePrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        srContextPublisher: SRContextPublisher,
        layerRecording: any LayerRecording,
        replaySampleRate: SampleRate,
        telemetry: any Telemetry,
        startRecordingImmediately: Bool
    ) {
        self.screenChangeMonitor = screenChangeMonitor
        self.textAndInputPrivacy = textAndInputPrivacy
        self.imagePrivacy = imagePrivacy
        self.touchPrivacy = touchPrivacy
        self.srContextPublisher = srContextPublisher
        self.layerRecording = layerRecording
        self.replaySampleRate = replaySampleRate
        self.telemetry = telemetry
        self.recordingEnabled = startRecordingImmediately

        srContextPublisher.setHasReplay(false)

        screenChangeMonitor.handler = { [weak self] changeset in
            Task { @MainActor [weak self] in
                await self?.scheduleRecording(changeset)
            }
        }
    }

    func startRecording() {
        Task { @MainActor [weak self] in
            self?.setRecordingEnabled(true)
        }
    }

    func stopRecording() {
        Task { @MainActor [weak self] in
            self?.setRecordingEnabled(false)
        }
    }

    @MainActor
    private func setRecordingEnabled(_ isEnabled: Bool) {
        recordingEnabled = isEnabled
        evaluateRecordingConditions()
    }

    @MainActor
    private func onRUMContextChanged(rumContext: RUMCoreContext?) {
        guard currentRUMContext != rumContext else {
            return
        }

        if currentRUMContext?.sessionID != rumContext?.sessionID || currentRUMContext == nil {
            if let sampler = rumContext?.sessionSampler {
                isSampled = sampler.combined(with: replaySampleRate).sample()
            } else {
                isSampled = Sampler(samplingRate: replaySampleRate).sample()
            }
        }

        currentRUMContext = rumContext

        evaluateRecordingConditions()
    }

    @MainActor
    private func evaluateRecordingConditions() {
        if recordingEnabled && isSampled {
            screenChangeMonitor.start()
        } else {
            screenChangeMonitor.stop()
        }
        updateHasReplay()
    }

    @MainActor
    private func updateHasReplay() {
        srContextPublisher.setHasReplay(isSampled && recordingEnabled)
    }

    @MainActor
    private func scheduleRecording(_ changeset: CALayerChangeset) async {
        guard recordingEnabled, isSampled else {
            return
        }

        guard let rumContext = currentRUMContext,
              let viewID = rumContext.viewID else {
            return
        }

        let context = LayerRecordingContext(
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            applicationID: rumContext.applicationID,
            sessionID: rumContext.sessionID,
            viewID: viewID,
            viewServerTimeOffset: rumContext.viewServerTimeOffset,
            viewPath: rumContext.viewPath,
            date: Date(),
            telemetry: telemetry
        )

        await layerRecording.scheduleRecording(changeset, context: context)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerTreeRecordingCoordinator: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from _: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        let rumContext = context.additionalContext(ofType: RUMCoreContext.self)

        Task { @MainActor [weak self] in
            self?.onRUMContextChanged(rumContext: rumContext)
        }

        return true
    }
}
#endif
