/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines dependency between RUM and Session Replay (SR) modules.
/// It aims at centralizing documentation of contracts between both product
internal struct SessionReplayDependency {
    /// The key referencing SR baggage in `DatadogContext.featuresAttributes`.
    ///
    /// RUM expects:
    /// - baggage with `hasReplay` key if SR Feature is configured;
    /// - the `hasReplay` baggege key of `Bool` value indicating if the replay is being recorded.
    static let srBaggageKey = "session-replay"

    /// The key referencing a `Bool` value that indicates if replay is being recorded.
    static let hasReplay = "has_replay"

    /// The key referencing a `[String: Int64]` value that indicates number of records recorded for a given viewID.
    static let recordsCountByViewID = "records_count_by_view_id"
}

// MARK: - Extracting SR context from `DatadogContext`

extension DatadogContext {
    /// The context of Session Replay Feature or `nil` if SR is not configured.
    var srBaggage: FeatureBaggage? {
        return featuresAttributes[SessionReplayDependency.srBaggageKey]
    }
}

extension FeatureBaggage {
    /// The value indicating if replay is being performed by Session Replay.
    var hasReplay: Bool {
        guard let hasReplay: Bool = self[SessionReplayDependency.hasReplay] else {
            return false
        }
        return hasReplay
    }

    /// The value of `[String: Int64]` that indicates number of records recorded for a given viewID.
    var recordsCountByViewID: [String: Int64] {
        guard let recordsCountByViewID: [String: Int64] = self[SessionReplayDependency.recordsCountByViewID] else {
            return [:]
        }
        return recordsCountByViewID
    }
}
