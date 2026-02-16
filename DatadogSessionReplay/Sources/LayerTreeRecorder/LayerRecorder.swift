/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
internal actor LayerRecorder: LayerRecording {
    private let layerProvider: any LayerProvider
    private var recordTask: Task<Void, Never>?

    init(layerProvider: any LayerProvider) {
        self.layerProvider = layerProvider
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

        // Pending stages:
        // - Render layer bitmaps
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
