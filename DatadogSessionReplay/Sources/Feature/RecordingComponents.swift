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
            // This is purely defensive, as `SessionReplay.enable()` initializes on the main thread,
            // but we still enforce main-thread execution here before assuming `MainActor` isolation
            // because `LayerTreeRecordingCoordinator` is @MainActor.
            self = try runOnMainThreadSync {
                try MainActor.assumeIsolated {
                    try .layerTreeRecordingComponents(core: core, configuration: configuration)
                }
            }
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

        let scheduler = try ScreenChangeScheduler(minimumInterval: 0.1, telemetry: telemetry)
        let contextReceiver = RUMContextReceiver()
        let viewTreeRecordingCoordinator = RecordingCoordinator(
            scheduler: scheduler,
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            rumContextObserver: contextReceiver,
            srContextPublisher: SRContextPublisher(core: core),
            recorder: recorder,
            sampler: Sampler(configuration: configuration),
            telemetry: telemetry,
            startRecordingImmediately: configuration.startRecordingImmediately
        )

        return .init(
            recordingCoordinator: viewTreeRecordingCoordinator,
            messageReceiver: contextReceiver
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @MainActor
    private static func layerTreeRecordingComponents(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration
    ) throws -> Self {
        let layerRecorder = LayerRecorder(layerProvider: KeyWindowObserver())
        let screenChangeMonitor = try ScreenChangeMonitor(minimumDeliveryInterval: 0.1)
        let telemetryQueue = BackgroundAsyncQueue(label: "com.datadoghq.session-replay.telemetry", qos: .background)
        let telemetry = SessionReplayTelemetry(
            telemetry: core.telemetry,
            queue: telemetryQueue
        )
        let layerTreeRecordingCoordinator = LayerTreeRecordingCoordinator(
            recorder: layerRecorder,
            screenChangeMonitor: screenChangeMonitor,
            replayContextPublisher: SRContextPublisher(core: core),
            telemetry: telemetry,
            sampler: Sampler(configuration: configuration),
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            startRecordingImmediately: configuration.startRecordingImmediately
        )

        return .init(
            recordingCoordinator: layerTreeRecordingCoordinator,
            messageReceiver: layerTreeRecordingCoordinator
        )
    }
}

extension Sampler {
    fileprivate init(configuration: SessionReplay.Configuration) {
        self.init(samplingRate: configuration.debugSDK ? 100 : configuration.replaySampleRate)
    }
}
#endif
