/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct RecordingComponents {
    let recordingCoordinator: any RecordingController
    let messageReceiver: any FeatureMessageReceiver

    init(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws {
        if #available(iOS 13.0, tvOS 13.0, *), configuration.featureFlags[.layerTreeRecording] {
            self = try .layerTreeRecordingComponents(core: core, configuration: configuration)
        } else {
            self = try .viewTreeRecordingComponents(core: core, configuration: configuration)
        }
    }

    private init(
        recordingCoordinator: any RecordingController,
        messageReceiver: any FeatureMessageReceiver
    ) {
        self.recordingCoordinator = recordingCoordinator
        self.messageReceiver = messageReceiver
    }

    private static func viewTreeRecordingComponents(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws -> Self {
        let processorsQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.processors", qos: .utility)
        // The telemetry queue targets the processors queue with a lower qos.
        let telemetryQueue = BackgroundAsyncQueue(
            label: "com.datadoghq.session-replay.telemetry",
            qos: .background,
            target: processorsQueue
        )

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
            core: core,
            featureFlags: configuration.featureFlags
        )

        let scheduler = ScreenChangeScheduler(minimumInterval: 0.1, telemetry: telemetry)
        let contextReceiver = RUMContextReceiver()
        let recordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            rumContextObserver: contextReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            replaySampleRate: configuration.debugSDK ? 100 : configuration.replaySampleRate,
            telemetry: telemetry,
            startRecordingImmediately: configuration.startRecordingImmediately
        )

        return .init(
            recordingCoordinator: recordingCoordinator,
            messageReceiver: contextReceiver
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private static func layerTreeRecordingComponents(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws -> Self {
        let telemetryQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.telemetry", qos: .background)
        let telemetry = SessionReplayTelemetry(
            telemetry: core.telemetry,
            queue: telemetryQueue
        )

        let screenChangeMonitor = try ScreenChangeMonitor(minimumDeliveryInterval: 0.1)
        let recordingCoordinator = LayerTreeRecordingCoordinator(
            screenChangeMonitor: screenChangeMonitor,
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            srContextPublisher: SRContextPublisher(core: core),
            layerRecording: LayerRecorder(),
            replaySampleRate: configuration.debugSDK ? 100 : configuration.replaySampleRate,
            telemetry: telemetry,
            startRecordingImmediately: configuration.startRecordingImmediately
        )

        return .init(
            recordingCoordinator: recordingCoordinator,
            messageReceiver: recordingCoordinator
        )
    }
}
#endif
