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

    // MARK: - Integrations with other features

    /// Updates other Features with SR context.
    private let contextPublisher: SRContextPublisher

    // MARK: - Main Components

    private let recorder: Recording
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
            writer: writer
        )

        let messageReceiver = RUMContextReceiver()
        let recorder = try Recorder(
            configuration: configuration,
            rumContextObserver: messageReceiver,
            processor: processor
        )

        self.messageReceiver = messageReceiver
        self.recorder = recorder
        self.processor = processor
        self.writer = writer
        self.requestBuilder = RequestBuilder(customUploadURL: configuration.customUploadURL)
        self.contextPublisher = SRContextPublisher(core: core)
        self.performanceOverride = PerformancePresetOverride(
            maxFileSize: UInt64(10).MB,
            maxObjectSize: UInt64(10).MB
        )
        // Set initial SR context (it is configured, but not yet started):
        contextPublisher.setRecordingIsPending(false)
    }

    func register(sessionReplayScope: FeatureScope) {
        writer.startWriting(to: sessionReplayScope)
    }

    // MARK: - SessionReplayController

    func start() {
        contextPublisher.setRecordingIsPending(true)
        recorder.start()
    }

    func stop() {
        contextPublisher.setRecordingIsPending(false)
        recorder.stop()
    }

    func change(privacy: SessionReplayPrivacy) { recorder.change(privacy: privacy) }
}
