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
        // 1. [main thread] Capture layer tree snapshot
        // 2. Optimize and flatten layer tree snapshots
        // 3. [main thread] Render layer bitmaps
        // 4. Process layer tree snapshots
    }
}
#endif
