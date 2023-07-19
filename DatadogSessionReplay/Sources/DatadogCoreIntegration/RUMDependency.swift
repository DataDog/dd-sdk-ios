/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines dependency between Session Replay (SR) and RUM modules.
/// It aims at centralizing documentation of contracts between both products.
internal enum RUMDependency {
    // MARK: Contract from RUM to SR:

    /// The key for referencing RUM baggage (RUM context) in `DatadogContext.featuresAttributes`.
    ///
    /// SR expects:
    /// - empty baggage (`[:]`) if current RUM session is not sampled,
    /// - baggage with `ids` and `serverTimeOffsetKey` keys if RUM session is sampled.
    static let rumBaggageKey = "rum"

    /// The key referencing server time offset of current RUM view used for date correction.
    ///
    /// SR expects non-optional value of `TimeInterval`.
    static let serverTimeOffsetKey = "server_time_offset"

    /// The key for referencing RUM baggage (RUM context) ids in `DatadogContext.featuresAttributes`.
    ///
    /// SR expects:
    /// - `nil` if current RUM session is not sampled,
    /// - baggage with `application.id`, `session.id` and `view.id` keys if RUM session is sampled.
    static let ids = "ids"

    // MARK: Contract from SR to RUM (mirror of `SessionReplayDependency` in RUM):

    /// The key referencing SR baggage in `DatadogContext.featuresAttributes`.
    ///
    /// RUM expects:
    /// - baggage with `hasReplay` key if SR Feature is configured;
    /// - the `hasReplay` baggege key of `Bool` value indicating if the replay is being recorded.
    static let srBaggageKey = "session-replay"

    /// The key referencing a `Bool` value that indicates if replay is being recorded.
    static let hasReplay = "has_replay"

    /// They key referencing a `[String: Int64]` dictionary of viewIDs and associated records count.
    static let recordsCountByViewID = "records_count_by_view_id"
}
