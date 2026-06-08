/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Outer envelope wrapping one or more `ClientStatsPayload`s (typically one per tracer).
///
/// See https://github.com/DataDog/datadog-agent/blob/main/pkg/proto/datadog/trace/stats.proto
///
/// Field names and order match the mobile-relevant subset of `StatsPayload.EncodeMsg` in
/// `stats_gen.go`. `agentHostname`, `agentEnv`, and `agentVersion` are intentionally empty
/// on mobile because no agent is in the upload path (the SDK uploads directly to the intake).
/// `clientComputed` is always `true`.
internal struct StatsPayload: Encodable {
    let clientStats: [ClientStatsPayload]
    let splitPayload: Bool

    private enum CodingKeys: String, CodingKey {
        case agentHostname = "AgentHostname"
        case agentEnv = "AgentEnv"
        case stats = "Stats"
        case agentVersion = "AgentVersion"
        case clientComputed = "ClientComputed"
        case splitPayload = "SplitPayload"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("", forKey: .agentHostname)
        try container.encode("", forKey: .agentEnv)
        try container.encode(clientStats, forKey: .stats)
        try container.encode("", forKey: .agentVersion)
        try container.encode(true, forKey: .clientComputed)
        try container.encode(splitPayload, forKey: .splitPayload)
    }
}
