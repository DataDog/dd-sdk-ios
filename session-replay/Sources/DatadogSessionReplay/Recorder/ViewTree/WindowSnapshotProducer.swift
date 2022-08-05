/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

/// Captures `ViewTreeSnapshot` in current application window.
internal struct WindowSnapshotProducer: ViewTreeSnapshotProducer {
    /// Finds the right window to capture snapshot in.
    let windowObserver: AppWindowObserver

    func takeSnapshot() -> ViewTreeSnapshot? {
        guard let window = windowObserver.relevantWindow else {
            return nil
        }
        return takeSnapshot(in: window)
    }

    private func takeSnapshot(in window: UIWindow) -> ViewTreeSnapshot {
        let now = Date()
        return ViewTreeSnapshot(date: now)
    }
}
