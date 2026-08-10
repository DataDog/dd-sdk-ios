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
        configuration: SessionReplay.Configuration,
        resourcesWriter: any ResourcesWriting,
        srContextPublisher: SRContextPublisher
    ) throws {
        if #available(iOS 13.0, tvOS 13.0, *), configuration.featureFlags[.compositionTreeRecording] {
            // This is purely defensive, as `SessionReplay.enable()` initializes on the main thread
            self = try runOnMainThreadSync {
                try .layerTreeRecordingComponents(
                    core: core,
                    configuration: configuration,
                    resourcesWriter: resourcesWriter,
                    srContextPublisher: srContextPublisher
                )
            }
        } else {
            self = try .viewTreeRecordingComponents(
                core: core,
                configuration: configuration,
                resourcesWriter: resourcesWriter,
                srContextPublisher: srContextPublisher
            )
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
        configuration: SessionReplay.Configuration,
        resourcesWriter: any ResourcesWriting,
        srContextPublisher: SRContextPublisher
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
            resourcesWriter: resourcesWriter
        )

        let snapshotProcessor = SnapshotProcessor(
            queue: processorsQueue,
            recordWriter: RecordWriter(core: core),
            resourceProcessor: resourceProcessor,
            srContextPublisher: srContextPublisher,
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
            srContextPublisher: srContextPublisher,
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
    @MainActor
    private static func layerTreeRecordingComponents(
        core: DatadogCoreProtocol,
        configuration: SessionReplay.Configuration,
        resourcesWriter: any ResourcesWriting,
        srContextPublisher: SRContextPublisher
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
            resourcesWriter: resourcesWriter
        )
        let snapshotProcessor = LayerSnapshotProcessor(
            queue: processorsQueue,
            recordWriter: RecordWriter(core: core),
            resourceProcessor: resourceProcessor,
            replayContextPublisher: srContextPublisher,
            telemetry: telemetry
        )

        let keyWindowObserver = KeyWindowObserver()
        let touchSnapshotProducer = WindowTouchSnapshotProducer(windowObserver: keyWindowObserver)
        let screenChangeFilter = ScreenChangeFilter()
        let layerRecorder = LayerRecorder(
            snapshotBuilder: LayerTreeSnapshotBuilder(layerProvider: keyWindowObserver),
            uiApplicationSwizzler: try UIApplicationSwizzler(handler: touchSnapshotProducer),
            touchSnapshotProducer: touchSnapshotProducer,
            imageSnapshotter: ImageSnapshotter(
                screenChangeFilter: screenChangeFilter,
                telemetry: telemetry
            ),
            snapshotProcessor: snapshotProcessor
        )
        let screenChangeMonitor = try ScreenChangeMonitor(
            minimumDeliveryInterval: 0.1,
            screenChangeFilter: screenChangeFilter
        )
        let recordingCoordinator = LayerTreeRecordingCoordinator(
            screenChangeMonitor: screenChangeMonitor,
            textAndInputPrivacy: configuration.textAndInputPrivacyLevel,
            imagePrivacy: configuration.imagePrivacyLevel,
            touchPrivacy: configuration.touchPrivacyLevel,
            srContextPublisher: srContextPublisher,
            layerRecording: layerRecorder,
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
