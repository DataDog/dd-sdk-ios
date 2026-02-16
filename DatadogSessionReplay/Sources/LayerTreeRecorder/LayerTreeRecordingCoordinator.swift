/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Main-actor coordinator for the layer-tree recording strategy.
//
// It combines RUM context updates, replay sampling, and start/stop lifecycle control to
// decide when recording is active. When active, it forwards batched screen changes from
// `ScreenChangeMonitor` to `LayerRecorder` with per-capture context metadata.

#if os(iOS)
import Foundation
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
internal class LayerTreeRecordingCoordinator: RecordingController {
    nonisolated let sampler: Sampler
    nonisolated let textAndInputPrivacy: TextAndInputPrivacyLevel
    nonisolated let imagePrivacy: ImagePrivacyLevel
    nonisolated let touchPrivacy: TouchPrivacyLevel

    private let recorder: any LayerRecording
    private let screenChangeMonitor: ScreenChangeMonitor
    private let replayContextPublisher: SRContextPublisher
    private let telemetry: any Telemetry

    private var rumContext: RUMCoreContext? = nil
    private var isSampled = false
    private var isRecordingStarted = false

    init(
        recorder: LayerRecorder,
        screenChangeMonitor: ScreenChangeMonitor,
        replayContextPublisher: SRContextPublisher,
        telemetry: any Telemetry,
        sampler: Sampler,
        textAndInputPrivacy: TextAndInputPrivacyLevel,
        imagePrivacy: ImagePrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        startRecordingImmediately: Bool
    ) {
        self.recorder = recorder
        self.screenChangeMonitor = screenChangeMonitor
        self.replayContextPublisher = replayContextPublisher
        self.telemetry = telemetry
        self.sampler = sampler
        self.textAndInputPrivacy = textAndInputPrivacy
        self.imagePrivacy = imagePrivacy
        self.touchPrivacy = touchPrivacy

        replayContextPublisher.setHasReplay(false)

        screenChangeMonitor.handler = { [weak self] changes in
            Task { @MainActor in
                await self?.scheduleRecording(changes)
            }
        }

        if startRecordingImmediately {
            _startRecording()
        }
    }

    nonisolated func startRecording() {
        Task { @MainActor in
            _startRecording()
        }
    }

    nonisolated func stopRecording() {
        Task { @MainActor in
            _stopRecording()
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerTreeRecordingCoordinator: FeatureMessageReceiver {
    nonisolated func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        let rumContext = context.additionalContext(ofType: RUMCoreContext.self)

        Task { @MainActor in
            onRUMContextChanged(rumContext)
        }

        return true
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerTreeRecordingCoordinator {
    private func onRUMContextChanged(_ rumContext: RUMCoreContext?) {
        guard self.rumContext != rumContext else {
            return
        }

        if self.rumContext?.sessionID != rumContext?.sessionID || self.rumContext == nil {
            isSampled = sampler.sample()
        }

        self.rumContext = rumContext

        startOrStopRecording()
    }

    private func _startRecording() {
        isRecordingStarted = true
        startOrStopRecording()
    }

    private func _stopRecording() {
        isRecordingStarted = false
        startOrStopRecording()
    }

    private func startOrStopRecording() {
        if isRecordingStarted, isSampled {
            screenChangeMonitor.start()
        } else {
            screenChangeMonitor.stop()
        }
        replayContextPublisher.setHasReplay(isSampled && isRecordingStarted)
    }

    private func scheduleRecording(_ changes: CALayerChangeset) async {
        guard isRecordingStarted, isSampled else {
            return
        }

        guard let rumContext, let viewID = rumContext.viewID else {
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
            date: Date(),
            telemetry: telemetry
        )

        await recorder.scheduleRecording(changes, context: context)
    }
}
#endif
