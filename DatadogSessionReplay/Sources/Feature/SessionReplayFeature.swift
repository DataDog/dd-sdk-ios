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
    /// Processes each new snapshot on a background thread and transforms it into records.
    let processor: Processing

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        let processor = Processor(
            queue: BackgroundAsyncQueue(named: "com.datadoghq.session-replay.processor"),
            writer: RecordWriter(core: core),
            srContextPublisher: SRContextPublisher(core: core),
            telemetry: core.telemetry
        )

        let scheduler = MainThreadScheduler(interval: 0.1)
        let messageReceiver = RUMContextReceiver()

        let recorder = try Recorder(
            processor: processor,
            telemetry: core.telemetry,
            additionalNodeRecorders: configuration._additionalNodeRecorders
        )
        let recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            privacy: configuration.defaultPrivacyLevel,
            rumContextObserver: messageReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate)
        )

        self.messageReceiver = messageReceiver
        self.recordingCoordinator = recordingCoordinator
        self.processor = processor
        self.requestBuilder = SegmentRequestBuilder(
            customUploadURL: configuration.customEndpoint,
            telemetry: core.telemetry
        )
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: 10.MB.asUInt64(),
            maxObjectSize: 10.MB.asUInt64(),
            meanFileAge: nil,
            uploadDelay: nil
        )
    }
}
#endif
