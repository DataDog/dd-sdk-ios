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
internal struct ClientStatsPayload: Encodable {
    let hostname: String
    let env: String
    let version: String
    let service: String
    let tracerVersion: String
    let runtimeID: String
    let sequenceNumber: UInt64
    let stats: [ClientStatsBucket]

    private enum CodingKeys: String, CodingKey {
        case hostname = "Hostname"
        case env = "Env"
        case version = "Version"
        case stats = "Stats"
        case lang = "Lang"
        case tracerVersion = "TracerVersion"
        case runtimeID = "RuntimeID"
        case sequence = "Sequence"
        case service = "Service"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(env, forKey: .env)
        try container.encode(version, forKey: .version)
        try container.encode(stats, forKey: .stats)
        // Platform identifier on the wire, matching Android's `"android"`. Distinct from
        // the spans `lang` tag (`"swift"`); the stats intake keys off platform.
        try container.encode("ios", forKey: .lang)
        try container.encode(tracerVersion, forKey: .tracerVersion)
        try container.encode(runtimeID, forKey: .runtimeID)
        try container.encode(sequenceNumber, forKey: .sequence)
        try container.encode(service, forKey: .service)
    }
}

/// A time-bucketed group of `ClientGroupedStats` for a fixed `[start, start + duration[` window.
/// (Half-open at the right: a span ending exactly at `start + duration` belongs to the next bucket.)
///
/// Field names and order match the mobile-relevant subset of `ClientStatsBucket.EncodeMsg`
/// in `stats_gen.go`. `AgentTimeShift` is intentionally omitted because the mobile SDK is
/// agent-less.
internal struct ClientStatsBucket: Encodable {
    let start: UInt64
    let duration: UInt64
    let stats: [ClientGroupedStats]

    private enum CodingKeys: String, CodingKey {
        case start = "Start"
        case duration = "Duration"
        case stats = "Stats"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(stats, forKey: .stats)
    }
}

/// Per `(service, name, resource, ...)` aggregated stats within a single bucket.
///
/// Field names and order match the mobile-relevant subset of `ClientGroupedStats.EncodeMsg`
/// in `stats_gen.go`. Fields not yet in scope for the mobile v1 payload (`DBType`,
/// `HTTPMethod`, `HTTPEndpoint`, `SpanDerivedPrimaryTags`, `AdditionalMetricTags`) are
/// intentionally omitted; revisit when the v1.2.0 spec is updated for mobile.
/// `okSummary` and `errorSummary` carry the protobuf-encoded DDSketch summaries for the
/// OK and error latency distributions respectively. `Synthetics` is hardcoded `false`
/// (mobile SDK has no synthetic-test concept) and `GRPCStatusCode` is hardcoded `""`
/// (gRPC is not yet instrumented).
internal struct ClientGroupedStats: Encodable {
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

    private enum CodingKeys: String, CodingKey {
        case service = "Service"
        case name = "Name"
        case resource = "Resource"
        case httpStatusCode = "HTTPStatusCode"
        case type = "Type"
        case hits = "Hits"
        case errors = "Errors"
        case duration = "Duration"
        case okSummary = "OkSummary"
        case errorSummary = "ErrorSummary"
        case synthetics = "Synthetics"
        case topLevelHits = "TopLevelHits"
        case spanKind = "SpanKind"
        case peerTags = "PeerTags"
        case isTraceRoot = "IsTraceRoot"
        case grpcStatusCode = "GRPCStatusCode"
        case serviceSource = "srv_src"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encode(name, forKey: .name)
        try container.encode(resource, forKey: .resource)
        try container.encode(httpStatusCode, forKey: .httpStatusCode)
        try container.encode(type, forKey: .type)
        try container.encode(hits, forKey: .hits)
        try container.encode(errors, forKey: .errors)
        try container.encode(duration, forKey: .duration)
        try container.encode(okSummary, forKey: .okSummary)
        try container.encode(errorSummary, forKey: .errorSummary)
        try container.encode(false, forKey: .synthetics)
        try container.encode(topLevelHits, forKey: .topLevelHits)
        try container.encode(spanKind, forKey: .spanKind)
        try container.encode(peerTags, forKey: .peerTags)
        try container.encode(isTraceRoot, forKey: .isTraceRoot)
        try container.encode("", forKey: .grpcStatusCode)
        try container.encode(serviceSource, forKey: .serviceSource)
    }
}
