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
    private let layerProvider: any LayerProvider
    private let layerImageRenderer: any LayerImageRendering
    private let timeoutInterval: TimeInterval
    private let timeSource: any TimeSource

    private var recordTask: Task<Void, Never>?

    init(
        layerProvider: any LayerProvider,
        layerImageRenderer: any LayerImageRendering,
        timeoutInterval: TimeInterval,
        timeSource: any TimeSource = .mediaTime
    ) {
        self.layerProvider = layerProvider
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
            let snapshot = await LayerSnapshot(using: layerProvider),
            // Prune, flatten and cull layer snapshots
            let targetSnapshots = snapshot
                .removingInvisible()?
                .flattened()
                .removingObscured(in: snapshot.clipRect),
            !targetSnapshots.isEmpty
        else {
            // There is nothing visible yet
            return
        }

        let elapsed = timeSource.now - startTime
        let remaining = max(0, timeoutInterval - elapsed)

        let layerImages = await layerImageRenderer.renderImages(
            for: targetSnapshots,
            changes: changes,
            rootLayer: snapshot.layer,
            timeoutInterval: remaining
        )

        // Pending stages:
        // - Process layer tree snapshots
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    @MainActor
    fileprivate init?(using layerProvider: any LayerProvider) {
        guard let rootLayer = layerProvider.rootLayer else {
            return nil
        }
        self.init(from: rootLayer)
    }
}
#endif
