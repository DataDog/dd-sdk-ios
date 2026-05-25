/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Records layer tree changes.
///
/// Only one recording task runs at a time. New requests are ignored while the
/// current task is still running.
@available(iOS 13.0, tvOS 13.0, *)
internal actor LayerRecorder: LayerRecording {
    private let snapshotBuilder: any LayerTreeSnapshotBuilding
    private let uiApplicationSwizzler: UIApplicationSwizzler
    private let touchSnapshotProducer: any TouchSnapshotProducer

    private var recordTask: Task<Void, Never>?

    init(
        snapshotBuilder: any LayerTreeSnapshotBuilding,
        uiApplicationSwizzler: UIApplicationSwizzler,
        touchSnapshotProducer: any TouchSnapshotProducer
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.uiApplicationSwizzler = uiApplicationSwizzler
        self.touchSnapshotProducer = touchSnapshotProducer

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

    private func record(_: CALayerChangeset, context: LayerRecordingContext) async {
        let (layerTreeSnapshot, touchSnapshot) = await MainActor.run { [snapshotBuilder, touchSnapshotProducer] in
            let layerTreeSnapshot = snapshotBuilder.createSnapshot(context: context)
            let touchSnapshot = layerTreeSnapshot.flatMap { _ in
                touchSnapshotProducer.takeSnapshot(
                    context: .init(
                        touchPrivacy: context.touchPrivacy,
                        viewServerTimeOffset: context.viewServerTimeOffset
                    )
                )
            }

            return (layerTreeSnapshot, touchSnapshot)
        }

        guard let layerTreeSnapshot else {
            return
        }

        _ = (layerTreeSnapshot, touchSnapshot)
        // TODO: PANA-7436 Process captured layer tree and touch snapshots
    }
}
#endif
