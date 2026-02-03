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
    let recordingCoordinator: RecordingCoordinator

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        let processorsQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.processors", qos: .utility)
        // The telemetry queue targets the processors queue with a lower qos.
        let telemetryQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.telemetry", qos: .background, target: processorsQueue)

        let telemetry = SessionReplayTelemetry(
            telemetry: core.telemetry,
            queue: telemetryQueue
        )

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

        let scheduler: any Scheduler = configuration.featureFlags[.screenChangeScheduling]
            ? ScreenChangeScheduler(minimumInterval: 0.1, telemetry: telemetry)
            : MainThreadScheduler(interval: 0.1)
        let contextReceiver = RUMContextReceiver()

        self.messageReceiver = CombinedFeatureMessageReceiver([
            contextReceiver,
            WebViewRecordReceiver(
                scope: core.scope(for: SessionReplayFeature.self)
            )
        ])

        self.textAndInputPrivacyLevel = configuration.textAndInputPrivacyLevel
        self.imagePrivacyLevel = configuration.imagePrivacyLevel
        self.touchPrivacyLevel = configuration.touchPrivacyLevel

        self.recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            rumContextObserver: contextReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate),
            telemetry: telemetry,
            startRecordingImmediately: configuration.startRecordingImmediately
        )
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
    }

    func startRecording() {
        self.recordingCoordinator.startRecording()
    }

    func stopRecording() {
        self.recordingCoordinator.stopRecording()
    }
}
#endif
