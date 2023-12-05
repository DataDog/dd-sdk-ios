/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Produces `ViewTreeSnapshot` of the key window in current application.
internal struct WindowViewTreeSnapshotProducer: ViewTreeSnapshotProducer {
    /// Finds the right window to capture snapshot in.
    let windowObserver: AppWindowObserver
    /// Builds snapshot from the app window.
    let snapshotBuilder: ViewTreeSnapshotBuilder

    func takeSnapshot(with context: Recorder.Context) throws -> ViewTreeSnapshot? {
        guard let window = windowObserver.relevantWindow else {
            return nil
        }
        return snapshotBuilder.createSnapshot(of: window, with: context)
    }
}
#endif
