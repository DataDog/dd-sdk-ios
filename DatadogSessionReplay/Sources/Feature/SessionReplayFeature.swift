/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal class SessionReplayFeature: SessionReplayConfiguration, DatadogRemoteFeature {
    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?
    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel
    let touchPrivacyLevel: TouchPrivacyLevel

    // MARK: - Main Components

    /// Orchestrates the process of capturing next snapshots on the main thread.
    let recordingCoordinator: any RecordingController

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        self.textAndInputPrivacyLevel = configuration.textAndInputPrivacyLevel
        self.imagePrivacyLevel = configuration.imagePrivacyLevel
        self.touchPrivacyLevel = configuration.touchPrivacyLevel

        let processorsQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.processors", qos: .utility)
        // The telemetry queue targets the processors queue with a lower qos.
        let telemetryQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.telemetry", qos: .background, target: processorsQueue)

        let telemetry = SessionReplayTelemetry(
            telemetry: core.telemetry,
            queue: telemetryQueue
        )

        let replayContextPublisher = SRContextPublisher(core: core)
        let sampler = Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate)
        let webViewRecordReceiver = WebViewRecordReceiver(scope: core.scope(for: SessionReplayFeature.self))

        self.requestBuilder = SegmentRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: SessionReplay.maxObjectSize,
            maxObjectSize: SessionReplay.maxObjectSize,
            meanFileAge: 2, // vs 5s with `batchSize: .small` - see `DatadogCore.PerformancePreset`
            maxFileAgeForRead: 5.hours, // Session Replay intake max age is 5 hours
            uploadDelay: (
                initial: 2, // vs 5s with `uploadFrequency: .frequent`
                range: 0.6..<6, // vs 1s ..< 10s with `uploadFrequency: .frequent`
                changeRate: 0.75 // vs 0.1 with `uploadFrequency: .frequent`
            )
        )

        if #available(iOS 13.0, tvOS 13.0, *), configuration.featureFlags[.layerTreeRecording] {
            precondition(Thread.isMainThread, "SessionReplayFeature must be initialized on main thread")

            let layerRecorder = LayerRecorder(layerProvider: KeyWindowObserver())
            let screenChangeMonitor = try ScreenChangeMonitor(minimumDeliveryInterval: 0.1)
            let layerTreeRecordingCoordinator = MainActor.assumeIsolated {
                LayerTreeRecordingCoordinator(
                    recorder: layerRecorder,
                    screenChangeMonitor: screenChangeMonitor,
                    replayContextPublisher: replayContextPublisher,
                    telemetry: telemetry,
                    sampler: sampler,
                    textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
                    imagePrivacy: configuration.imagePrivacyLevel,
                    touchPrivacy: configuration.touchPrivacyLevel,
                    startRecordingImmediately: configuration.startRecordingImmediately
                )
            }
            self.messageReceiver = CombinedFeatureMessageReceiver(
                [layerTreeRecordingCoordinator, webViewRecordReceiver]
            )
            self.recordingCoordinator = layerTreeRecordingCoordinator
        } else {
            let resourceProcessor = ResourceProcessor(
                queue: processorsQueue,
                resourcesWriter: ResourcesWriter(scope: core.scope(for: ResourcesFeature.self))
            )

            let snapshotProcessor = SnapshotProcessor(
                queue: processorsQueue,
                recordWriter: RecordWriter(core: core),
                resourceProcessor: resourceProcessor,
                srContextPublisher: SRContextPublisher(core: core),
                telemetry: telemetry
            )

            let recorder = try Recorder(
                snapshotProcessor: snapshotProcessor,
                additionalNodeRecorders: configuration._additionalNodeRecorders,
                featureFlags: configuration.featureFlags
            )

            let scheduler = try ScreenChangeScheduler(minimumInterval: 0.1, telemetry: telemetry)
            let contextReceiver = RUMContextReceiver()

            self.messageReceiver = CombinedFeatureMessageReceiver(
                [contextReceiver, webViewRecordReceiver]
            )

            self.recordingCoordinator = RecordingCoordinator(
                scheduler: scheduler,
                textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
                imagePrivacy: configuration.imagePrivacyLevel,
                touchPrivacy: configuration.touchPrivacyLevel,
                rumContextObserver: contextReceiver,
                srContextPublisher: replayContextPublisher,
                recorder: recorder,
                sampler: sampler,
                telemetry: telemetry,
                startRecordingImmediately: configuration.startRecordingImmediately
            )
        }
    }

    func startRecording() {
        self.recordingCoordinator.startRecording()
    }

    func stopRecording() {
        self.recordingCoordinator.stopRecording()
    }
}
#endif
