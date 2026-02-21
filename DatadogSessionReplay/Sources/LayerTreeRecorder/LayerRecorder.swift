/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Actor entry point for layer-tree recording.
//
// It serializes recording work and intentionally drops new scheduling requests while
// a capture task is in flight to avoid re-entrancy. The current pipeline scaffolding
// captures a snapshot, removes invisible branches, flattens the tree, and culls fully
// obscured layers before moving to rendering/processing stages.

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal actor LayerRecorder: LayerRecording {
    private let snapshotBuilder: any LayerTreeSnapshotBuilding
    private let layerImageRenderer: any LayerImageRendering
    private let timeoutInterval: TimeInterval
    private let timeSource: any TimeSource

    private var recordTask: Task<Void, Never>?

    init(
        snapshotBuilder: any LayerTreeSnapshotBuilding,
        layerImageRenderer: any LayerImageRendering,
        timeoutInterval: TimeInterval,
        timeSource: any TimeSource = .mediaTime
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.layerImageRenderer = layerImageRenderer
        self.timeoutInterval = max(0, timeoutInterval)
        self.timeSource = timeSource
    }

    func scheduleRecording(_ changes: CALayerChangeset, context: LayerRecordingContext) {
        guard recordTask == nil else {
            return
        }

        recordTask = Task {
            await self.record(changes, context: context)
            recordTask = nil
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerRecorder {
    private func record(_ changes: CALayerChangeset, context: LayerRecordingContext) async {
        let startTime = timeSource.now

        guard
            // Capture layer tree snapshot
            let layerTreeSnapshot = await snapshotBuilder.createSnapshot(context: context),
            // Prune, flatten and cull layer snapshots
            let targetSnapshots = layerTreeSnapshot.root
                .removingInvisible()?
                .flattened()
                .removingObscured(in: layerTreeSnapshot.root.clipRect),
            !targetSnapshots.isEmpty
        else {
            // There is nothing visible yet
            return
        }

        let elapsed = timeSource.now - startTime
        let remaining = max(0, timeoutInterval - elapsed)

        _ = await layerImageRenderer.renderImages(
            for: targetSnapshots,
            changes: changes,
            rootLayer: layerTreeSnapshot.root.layer,
            timeoutInterval: remaining
        )

        // Pending stages:
        // - Process layer tree snapshots
    }
}
#endif
