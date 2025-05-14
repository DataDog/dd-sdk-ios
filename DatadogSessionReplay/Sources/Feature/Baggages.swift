/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines dependency between Session Replay (SR) and RUM modules.
/// It aims at centralizing documentation of contracts between both products.
internal enum RUMDependency {
    // MARK: Contract from SR to RUM (mirror of `SessionReplayDependency` in RUM):

    /// The key referencing a `Bool` value that indicates if replay is being recorded.
    static let hasReplay = "sr_has_replay"

    /// They key referencing a `[String: Int64]` dictionary of viewIDs and associated records count.
    static let recordsCountByViewID = "sr_records_count_by_view_id"
}
