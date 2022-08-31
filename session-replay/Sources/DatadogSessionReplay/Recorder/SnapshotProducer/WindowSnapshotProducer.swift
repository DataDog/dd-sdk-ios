/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

/// Produces `ViewTreeSnapshot` for key window in current application.
internal struct WindowSnapshotProducer: ViewTreeSnapshotProducer {
    /// Finds the right window to capture snapshot in.
    let windowObserver: AppWindowObserver
    /// Builds snapshot from the app window.
    let snapshotBuilder: ViewTreeSnapshotBuilder

    func takeSnapshot() throws -> ViewTreeSnapshot? {
        guard let window = windowObserver.relevantWindow else {
            return nil
        }
        return snapshotBuilder.createSnapshot(of: window)
    }
}
