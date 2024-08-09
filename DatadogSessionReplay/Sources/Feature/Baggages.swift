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

/// The RUM context received from `DatadogCore`.
internal struct RUMContext: Codable, Equatable {
    static let key = "rum"

    enum CodingKeys: String, CodingKey {
        case applicationID = "application.id"
        case sessionID = "session.id"
        case viewID = "view.id"
        case viewServerTimeOffset = "server_time_offset"
    }

    /// Current RUM application ID - standard UUID string, lowecased.
    let applicationID: String
    /// Current RUM session ID - standard UUID string, lowecased.
    let sessionID: String
    /// Current RUM view ID - standard UUID string, lowecased. It can be empty when view is being loaded.
    let viewID: String?
    /// Current view related server time offset
    let viewServerTimeOffset: TimeInterval?
}
