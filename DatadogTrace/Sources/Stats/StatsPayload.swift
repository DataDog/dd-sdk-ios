/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Outer envelope for one or more pre-encoded `ClientStatsPayload` byte sequences.
///
/// See https://github.com/DataDog/datadog-agent/blob/main/pkg/proto/datadog/trace/stats.proto
///
/// Field names and order match `StatsPayload.EncodeMsg` in `stats_gen.go`. `agentHostname`,
/// `agentEnv`, and `agentVersion` are intentionally empty on mobile because no agent is in the
/// upload path (the SDK uploads directly to the intake). `clientComputed` is always `true`.
internal struct StatsPayload {
    /// Pre-encoded MsgPack bytes for each `ClientStatsPayload` (typically one per tracer).
    let clientStats: [Data]
    let splitPayload: Bool

    func toMsgPackPayload() -> Data {
        let encoder = MsgPackEncoder()
        encoder.startMap(elementCount: Field.statsFieldCount)

        encoder.writeRawString(Field.agentHostname)
        encoder.writeRawString(Field.emptyString)

        encoder.writeRawString(Field.agentEnv)
        encoder.writeRawString(Field.emptyString)

        encoder.writeRawString(Field.stats)
        encoder.startArray(elementCount: clientStats.count)
        for bytes in clientStats {
            encoder.appendRawBytes(bytes)
        }

        encoder.writeRawString(Field.agentVersion)
        encoder.writeRawString(Field.emptyString)

        encoder.writeRawString(Field.clientComputed)
        encoder.writeBoolean(true)

        encoder.writeRawString(Field.splitPayload)
        encoder.writeBoolean(splitPayload)

        return encoder.getBytes()
    }

    private enum Field {
        static let statsFieldCount = 6
        static let agentHostname = Data("AgentHostname".utf8)
        static let agentEnv = Data("AgentEnv".utf8)
        static let agentVersion = Data("AgentVersion".utf8)
        static let stats = Data("Stats".utf8)
        static let clientComputed = Data("ClientComputed".utf8)
        static let splitPayload = Data("SplitPayload".utf8)
        static let emptyString = Data()
    }
}
