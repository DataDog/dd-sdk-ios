/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Tracks field changes between view updates to enable partial payloads
internal struct ViewUpdateTracker {
    /// Snapshot of view metrics for change detection
    struct ViewSnapshot {
        let timeSpent: Int64
        let actionCount: Int64
        let errorCount: Int64
        let resourceCount: Int64
        let longTaskCount: Int64
        let frozenFrameCount: Int64
        let frustrationCount: Int64
        // Add more fields as needed
    }

    private var previousSnapshot: ViewSnapshot?

    /// Captures current view state
    mutating func capture(
        timeSpent: Int64,
        actionCount: Int64,
        errorCount: Int64,
        resourceCount: Int64,
        longTaskCount: Int64,
        frozenFrameCount: Int64,
        frustrationCount: Int64
    ) -> ViewSnapshot {
        let snapshot = ViewSnapshot(
            timeSpent: timeSpent,
            actionCount: actionCount,
            errorCount: errorCount,
            resourceCount: resourceCount,
            longTaskCount: longTaskCount,
            frozenFrameCount: frozenFrameCount,
            frustrationCount: frustrationCount
        )
        defer { previousSnapshot = snapshot }
        return snapshot
    }

    /// Returns fields that changed since last capture
    func changedFields(current: ViewSnapshot) -> ChangedViewFields {
        guard let previous = previousSnapshot else {
            return ChangedViewFields(isFirstUpdate: true)
        }

        return ChangedViewFields(
            isFirstUpdate: false,
            timeSpent: current.timeSpent != previous.timeSpent ? current.timeSpent : nil,
            actionCount: current.actionCount != previous.actionCount ? current.actionCount : nil,
            errorCount: current.errorCount != previous.errorCount ? current.errorCount : nil,
            resourceCount: current.resourceCount != previous.resourceCount ? current.resourceCount : nil,
            longTaskCount: current.longTaskCount != previous.longTaskCount ? current.longTaskCount : nil,
            frozenFrameCount: current.frozenFrameCount != previous.frozenFrameCount ? current.frozenFrameCount : nil,
            frustrationCount: current.frustrationCount != previous.frustrationCount ? current.frustrationCount : nil
        )
    }
}

/// Container for changed fields (nil = unchanged)
internal struct ChangedViewFields {
    let isFirstUpdate: Bool
    var timeSpent: Int64?
    var actionCount: Int64?
    var errorCount: Int64?
    var resourceCount: Int64?
    var longTaskCount: Int64?
    var frozenFrameCount: Int64?
    var frustrationCount: Int64?

    init(
        isFirstUpdate: Bool,
        timeSpent: Int64? = nil,
        actionCount: Int64? = nil,
        errorCount: Int64? = nil,
        resourceCount: Int64? = nil,
        longTaskCount: Int64? = nil,
        frozenFrameCount: Int64? = nil,
        frustrationCount: Int64? = nil
    ) {
        self.isFirstUpdate = isFirstUpdate
        self.timeSpent = timeSpent
        self.actionCount = actionCount
        self.errorCount = errorCount
        self.resourceCount = resourceCount
        self.longTaskCount = longTaskCount
        self.frozenFrameCount = frozenFrameCount
        self.frustrationCount = frustrationCount
    }

    var hasChanges: Bool {
        timeSpent != nil || actionCount != nil || errorCount != nil ||
        resourceCount != nil || longTaskCount != nil || frozenFrameCount != nil ||
        frustrationCount != nil
    }
}
