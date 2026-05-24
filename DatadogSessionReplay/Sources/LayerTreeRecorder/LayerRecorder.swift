/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Records layer-tree changes.
///
/// Only one recording task runs at a time. New requests are ignored while the
/// current task is still running.
@available(iOS 13.0, tvOS 13.0, *)
internal actor LayerRecorder: LayerRecording {
    private var recordTask: Task<Void, Never>?

    func scheduleRecording(_ changeset: CALayerChangeset, context: LayerRecordingContext) async {
        guard recordTask == nil else {
            return
        }

        recordTask = Task {
            await self.record(changeset, context: context)
            recordTask = nil
        }
    }

    private func record(_: CALayerChangeset, context _: LayerRecordingContext) async {
        // TODO: PANA-1234 Implement recording
    }
}
#endif
