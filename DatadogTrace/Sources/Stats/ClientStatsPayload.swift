/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Per-tracer client-side stats payload.
///
/// See https://github.com/DataDog/datadog-agent/blob/main/pkg/proto/datadog/trace/stats.proto
///
/// Field names and order match the mobile-relevant subset of `ClientStatsPayload.EncodeMsg`
/// in `stats_gen.go`. Agent-side fields (`AgentAggregation`, `ContainerID`, `GitCommitSha`,
/// `ImageTag`, `ProcessTagsHash`, `ProcessTags`) are intentionally omitted because the mobile
/// SDK uploads to intake directly without a Datadog Agent. The encoded payload is
/// byte-for-byte aligned with the Android implementation to keep cross-platform parity.
internal struct ClientStatsPayload {
    let hostname: String
    let env: String
    let version: String
    let service: String
    let tracerVersion: String
    let runtimeID: String
    let sequenceNumber: UInt64
    let stats: [ClientStatsBucket]

    func toMsgPackPayload() -> Data {
        let encoder = MsgPackEncoder()
        encoder.startMap(elementCount: Field.payloadFieldCount)

        encoder.writeString(Field.hostname)
        encoder.writeString(hostname)

        encoder.writeString(Field.env)
        encoder.writeString(env)

        encoder.writeString(Field.version)
        encoder.writeString(version)

        encoder.writeString(Field.stats)
        encoder.startArray(elementCount: stats.count)
        for bucket in stats {
            bucket.encode(into: encoder)
        }

        encoder.writeString(Field.lang)
        encoder.writeString(Field.langValue)

        encoder.writeString(Field.tracerVersion)
        encoder.writeString(tracerVersion)

        encoder.writeString(Field.runtimeID)
        encoder.writeString(runtimeID)

        encoder.writeString(Field.sequence)
        encoder.writeULong(sequenceNumber)

        encoder.writeString(Field.service)
        encoder.writeString(service)

        return encoder.getBytes()
    }

    private enum Field {
        static let payloadFieldCount = 9
        static let hostname = "Hostname"
        static let env = "Env"
        static let version = "Version"
        static let stats = "Stats"
        static let lang = "Lang"
        /// Platform identifier on the wire, matching Android's `"android"`. Distinct
        /// from the spans `lang` tag (`"swift"`); the stats intake keys off platform,
        /// not language.
        static let langValue = "ios"
        static let tracerVersion = "TracerVersion"
        static let runtimeID = "RuntimeID"
        static let sequence = "Sequence"
        static let service = "Service"
    }
}

/// A time-bucketed group of `ClientGroupedStats` for a fixed `[start, start + duration[` window.
/// (Half-open at the right: a span ending exactly at `start + duration` belongs to the next bucket.)
///
/// Field names and order match the mobile-relevant subset of `ClientStatsBucket.EncodeMsg`
/// in `stats_gen.go`. `AgentTimeShift` is intentionally omitted because the mobile SDK is
/// agent-less.
internal struct ClientStatsBucket {
    let start: UInt64
    let duration: UInt64
    let stats: [ClientGroupedStats]

    func encode(into encoder: MsgPackEncoder) {
        encoder.startMap(elementCount: Field.bucketFieldCount)

        encoder.writeString(Field.start)
        encoder.writeULong(start)

        encoder.writeString(Field.duration)
        encoder.writeULong(duration)

        encoder.writeString(Field.stats)
        encoder.startArray(elementCount: stats.count)
        for grouped in stats {
            grouped.encode(into: encoder)
        }
    }

    private enum Field {
        static let bucketFieldCount = 3
        static let start = "Start"
        static let duration = "Duration"
        static let stats = "Stats"
    }
}

/// Per `(service, name, resource, ...)` aggregated stats within a single bucket.
///
/// Field names and order match the mobile-relevant subset of `ClientGroupedStats.EncodeMsg`
/// in `stats_gen.go`. Fields not yet in scope for the mobile v1 payload (`DBType`,
/// `HTTPMethod`, `HTTPEndpoint`, `SpanDerivedPrimaryTags`, `AdditionalMetricTags`) are
/// intentionally omitted; revisit when the v1.2.0 spec is updated for mobile.
/// `okSummary` and `errorSummary` carry the protobuf-encoded DDSketch summaries for the
/// OK and error latency distributions respectively.
internal struct ClientGroupedStats {
    let service: String
    let name: String
    let resource: String
    let httpStatusCode: UInt32
    let type: String
    let spanKind: String
    let isTraceRoot: Trilean
    let hits: UInt64
    let errors: UInt64
    let duration: UInt64
    let topLevelHits: UInt64
    let okSummary: Data
    let errorSummary: Data
    let peerTags: [String]
    let serviceSource: String

    func encode(into encoder: MsgPackEncoder) {
        encoder.startMap(elementCount: Field.groupedStatsFieldCount)

        encoder.writeString(Field.service)
        encoder.writeString(service)

        encoder.writeString(Field.name)
        encoder.writeString(name)

        encoder.writeString(Field.resource)
        encoder.writeString(resource)

        encoder.writeString(Field.httpStatusCode)
        encoder.writeUInt(httpStatusCode)

        encoder.writeString(Field.type)
        encoder.writeString(type)

        encoder.writeString(Field.hits)
        encoder.writeULong(hits)

        encoder.writeString(Field.errors)
        encoder.writeULong(errors)

        encoder.writeString(Field.duration)
        encoder.writeULong(duration)

        encoder.writeString(Field.okSummary)
        encoder.writeBinary(okSummary)

        encoder.writeString(Field.errorSummary)
        encoder.writeBinary(errorSummary)

        encoder.writeString(Field.synthetics)
        encoder.writeBoolean(false)

        encoder.writeString(Field.topLevelHits)
        encoder.writeULong(topLevelHits)

        encoder.writeString(Field.spanKind)
        encoder.writeString(spanKind)

        encoder.writeString(Field.peerTags)
        encoder.startArray(elementCount: peerTags.count)
        for tag in peerTags {
            encoder.writeString(tag)
        }

        encoder.writeString(Field.isTraceRoot)
        encoder.writeInt(Int32(isTraceRoot.rawValue))

        encoder.writeString(Field.grpcStatusCode)
        encoder.writeString("")

        encoder.writeString(Field.serviceSource)
        encoder.writeString(serviceSource)
    }

    private enum Field {
        static let groupedStatsFieldCount = 17
        static let service = "Service"
        static let name = "Name"
        static let resource = "Resource"
        static let httpStatusCode = "HTTPStatusCode"
        static let type = "Type"
        static let hits = "Hits"
        static let errors = "Errors"
        static let duration = "Duration"
        static let okSummary = "OkSummary"
        static let errorSummary = "ErrorSummary"
        static let synthetics = "Synthetics"
        static let topLevelHits = "TopLevelHits"
        static let spanKind = "SpanKind"
        static let peerTags = "PeerTags"
        static let isTraceRoot = "IsTraceRoot"
        static let grpcStatusCode = "GRPCStatusCode"
        static let serviceSource = "srv_src"
    }
}
