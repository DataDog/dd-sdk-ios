/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines dependency between RUM and Session Replay (SR) modules.
/// It aims at centralizing documentation of contracts between both product
internal struct SessionReplayDependency {
    /// The key referencing a `Bool` value that indicates if replay is being recorded.
    static let hasReplay = "sr_has_replay"

    /// The key referencing a `[String: Int64]` value that indicates number of records recorded for a given viewID.
    static let recordsCountByViewID = "sr_records_count_by_view_id"
}

// MARK: - Extracting SR context from `DatadogContext`

extension DatadogContext {
    /// The value indicating if replay is being performed by Session Replay.
    var hasReplay: Bool? {
        try? baggages[SessionReplayDependency.hasReplay]?.decode()
    }

    /// The value of `[String: Int64]` that indicates number of records recorded for a given viewID.
    var recordsCountByViewID: [String: Int64] {
        let records: [String: Int64]? = try? baggages[SessionReplayDependency.recordsCountByViewID]?.decode()
        return records ?? [:]
    }
}
