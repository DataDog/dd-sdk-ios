/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal class SessionReplayFeature: DatadogRemoteFeature {
    static let name: String = "session-replay"

    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    // MARK: - Main Components

    /// Orchestrates the process of capturing next snapshots on the main thread.
    let recordingCoordinator: RecordingCoordinator

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        let snapshotProcessor = SnapshotProcessor(
            queue: BackgroundAsyncQueue(named: "com.datadoghq.session-replay.snapshot-processor"),
            recordWriter: RecordWriter(core: core),
            srContextPublisher: SRContextPublisher(core: core),
            telemetry: core.telemetry
        )
        // RUM-2154 Disabled until prod backend is ready
        _ = ResourceProcessor(
            queue: BackgroundAsyncQueue(named: "com.datadoghq.session-replay.resource-processor"),
            resourcesWriter: ResourcesWriter(core: core)
        )
        let recorder = try Recorder(
            snapshotProcessor: snapshotProcessor,
            resourceProcessor: nil,
            telemetry: core.telemetry,
            additionalNodeRecorders: configuration._additionalNodeRecorders
        )
        let scheduler = MainThreadScheduler(interval: 0.1)
        let messageReceiver = RUMContextReceiver()

        self.messageReceiver = messageReceiver
        self.recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            privacy: configuration.defaultPrivacyLevel,
            rumContextObserver: messageReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate)
        )
        self.requestBuilder = SegmentRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: 10.MB.asUInt64(),
            maxObjectSize: 10.MB.asUInt64(),
            meanFileAge: 2, // vs 5s with `batchSize: .small` - see `DatadogCore.PerformancePreset`
            uploadDelay: (
                initial: 2, // vs 5s with `uploadFrequency: .frequent`
                range: 0.6..<6, // vs 1s ..< 10s with `uploadFrequency: .frequent`
                changeRate: 0.75 // vs 0.1 with `uploadFrequency: .frequent`
            )
        )
    }
}
#endif
