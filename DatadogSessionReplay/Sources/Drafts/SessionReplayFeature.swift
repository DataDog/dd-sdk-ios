/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// A draft of the main SR component (TODO: RUMM-2268 Design convenient public API).
/// - It conforms to `DatadogFeature` for communicating with `DatadogCore`.
/// - It implements `SessionReplayController` for being used from the public API.
///
/// An instance of `SessionReplayFeature` is kept by `DatadogCore` but can be also
/// retained by the user.
internal class SessionReplayFeature: DatadogFeature, SessionReplayController {
    // MARK: - DatadogFeature

    let name: String = "session-replay"
    let requestBuilder: FeatureRequestBuilder
    let messageReceiver: FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride?

    // MARK: - Main Components

    private let recordingCoordinator: RecordingCoordinator
    private let processor: Processing
    private let writer: Writing

    // MARK: - Initialization

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplayConfiguration
    ) throws {
        let writer = Writer()

        let processor = Processor(
            queue: BackgroundAsyncQueue(named: "com.datadoghq.session-replay.processor"),
            writer: writer,
            srContextPublisher: SRContextPublisher(core: core)
        )

        let scheduler = MainThreadScheduler(interval: 0.1)
        let messageReceiver = RUMContextReceiver()

        let recorder = try Recorder(
            processor: processor
        )
        let recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            privacy: configuration.privacy,
            rumContextObserver: messageReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(samplingRate: configuration.samplingRate)
        )

        self.messageReceiver = messageReceiver
        self.recordingCoordinator = recordingCoordinator
        self.processor = processor
        self.writer = writer
        self.requestBuilder = RequestBuilder(customUploadURL: configuration.customUploadURL)
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: UInt64(10).MB,
            maxObjectSize: UInt64(10).MB,
            meanFileAge: 5, // equivalent of `batchSize: .small` - see `DatadogCore.PerformancePreset`
            minUploadDelay: 1 // equivalent of `uploadFrequency: .frequent` - see `DatadogCore.PerformancePreset`
        )
    }

    func register(sessionReplayScope: FeatureScope) {
        writer.startWriting(to: sessionReplayScope)
    }
}
