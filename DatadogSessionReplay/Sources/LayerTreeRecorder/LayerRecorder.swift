/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@preconcurrency import DatadogInternal

/// Records layer tree changes.
///
/// Only one recording task runs at a time. New requests are ignored while the
/// current task is still running.
@available(iOS 13.0, tvOS 13.0, *)
internal actor LayerRecorder: LayerRecording {
    private let snapshotBuilder: any LayerTreeSnapshotBuilding
    private let uiApplicationSwizzler: UIApplicationSwizzler
    private let touchSnapshotProducer: any TouchSnapshotProducer
    private let imageSnapshotter: any ImageSnapshotting
    private let snapshotProcessor: any LayerSnapshotProcessing
    private let timeoutInterval: TimeInterval
    private let timeSource: any TimeSource

    private var recordTask: Task<Void, Never>?

    init(
        snapshotBuilder: any LayerTreeSnapshotBuilding,
        uiApplicationSwizzler: UIApplicationSwizzler,
        touchSnapshotProducer: any TouchSnapshotProducer,
        imageSnapshotter: any ImageSnapshotting,
        snapshotProcessor: any LayerSnapshotProcessing,
        timeoutInterval: TimeInterval = 0.09,
        timeSource: any TimeSource = MediaTimeSource()
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.touchSnapshotProducer = touchSnapshotProducer
        self.imageSnapshotter = imageSnapshotter
        self.snapshotProcessor = snapshotProcessor
        self.timeoutInterval = timeoutInterval
        self.timeSource = timeSource

        uiApplicationSwizzler.swizzle()
    }

    deinit {
        uiApplicationSwizzler.unswizzle()
    }

    func scheduleRecording(_ changeset: CALayerChangeset, context: LayerRecordingContext) async {
        guard recordTask == nil else {
            return
        }

        recordTask = Task {
            await self.record(changeset, context: context)
            recordTask = nil
        }
    }

    private func record(_ changeset: CALayerChangeset, context: LayerRecordingContext) async {
        let startTime = timeSource.now
        let (layerTreeSnapshot, touchSnapshot) = await takeSnapshot(
            context: context,
            snapshotBuilder: snapshotBuilder,
            touchSnapshotProducer: touchSnapshotProducer
        )

        guard
            var layerTreeSnapshot,
            let root = layerTreeSnapshot.root
                .resolvingPortalLayers()
                .removingOccluded()
        else {
            return
        }

        layerTreeSnapshot.root = root

        let remainingTime = max(0, timeoutInterval - (timeSource.now - startTime))
        let imageSnapshots = await imageSnapshotter.takeImageSnapshots(
            for: layerTreeSnapshot.root,
            changeset: changeset,
            timeout: remainingTime
        )

        snapshotProcessor.process(
            layerTreeSnapshot: layerTreeSnapshot,
            imageSnapshots: imageSnapshots,
            touchSnapshot: touchSnapshot
        )
    }

    @MainActor
    private func takeSnapshot(
        context: LayerRecordingContext,
        snapshotBuilder: any LayerTreeSnapshotBuilding,
        touchSnapshotProducer: any TouchSnapshotProducer
    ) -> (LayerTreeSnapshot?, TouchSnapshot?) {
        do {
            return try objc_rethrow { () -> (LayerTreeSnapshot?, TouchSnapshot?) in
                guard let layerTreeSnapshot = snapshotBuilder.takeSnapshot(context: context) else {
                    return (nil, nil)
                }
                let touchSnapshot = touchSnapshotProducer.takeSnapshot(
                    context: .init(
                        touchPrivacy: context.touchPrivacy,
                        viewServerTimeOffset: context.viewServerTimeOffset
                    )
                )
                return (layerTreeSnapshot, touchSnapshot)
            }
        } catch let objc as ObjcException {
            context.telemetry.error(
                "[SR] Failed to take snapshot due to Objective-C runtime exception",
                error: objc.error
            )
            return (nil, nil)
        } catch {
            context.telemetry.error("[SR] Failed to take snapshot", error: error)
            return (nil, nil)
        }
    }
}
#endif
