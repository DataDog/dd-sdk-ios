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
/// Field names and order match `ClientStatsPayload.EncodeMsg` in `stats_gen.go`. The wire format
/// is byte-for-byte aligned with the Android implementation to keep cross-platform parity.
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

        encoder.writeRawString(Field.hostname)
        encoder.writeString(hostname)

        encoder.writeRawString(Field.env)
        encoder.writeString(env)

        encoder.writeRawString(Field.version)
        encoder.writeString(version)

        encoder.writeRawString(Field.stats)
        encoder.startArray(elementCount: stats.count)
        for bucket in stats {
            bucket.encode(into: encoder)
        }

        encoder.writeRawString(Field.lang)
        encoder.writeRawString(Field.langValue)

        encoder.writeRawString(Field.tracerVersion)
        encoder.writeString(tracerVersion)

        encoder.writeRawString(Field.runtimeID)
        encoder.writeString(runtimeID)

        encoder.writeRawString(Field.sequence)
        encoder.writeULong(sequenceNumber)

        encoder.writeRawString(Field.service)
        encoder.writeString(service)

        return encoder.getBytes()
    }

    private enum Field {
        static let payloadFieldCount = 9
        static let hostname = Data("Hostname".utf8)
        static let env = Data("Env".utf8)
        static let version = Data("Version".utf8)
        static let stats = Data("Stats".utf8)
        static let lang = Data("Lang".utf8)
        /// Platform identifier on the wire, matching Android's `"android"`. Distinct
        /// from the spans `lang` tag (`"swift"`); the stats intake keys off platform,
        /// not language.
        static let langValue = Data("ios".utf8)
        static let tracerVersion = Data("TracerVersion".utf8)
        static let runtimeID = Data("RuntimeID".utf8)
        static let sequence = Data("Sequence".utf8)
        static let service = Data("Service".utf8)
    }
}

/// A time-bucketed group of `ClientGroupedStats` for a fixed `[start, start + duration)` window.
///
/// Field names and order match `ClientStatsBucket.EncodeMsg` in `stats_gen.go`.
internal struct ClientStatsBucket {
    let start: UInt64
    let duration: UInt64
    let stats: [ClientGroupedStats]

    func encode(into encoder: MsgPackEncoder) {
        encoder.startMap(elementCount: Field.bucketFieldCount)

        encoder.writeRawString(Field.start)
        encoder.writeULong(start)

        encoder.writeRawString(Field.duration)
        encoder.writeULong(duration)

        encoder.writeRawString(Field.stats)
        encoder.startArray(elementCount: stats.count)
        for grouped in stats {
            grouped.encode(into: encoder)
        }
    }

    private enum Field {
        static let bucketFieldCount = 3
        static let start = Data("Start".utf8)
        static let duration = Data("Duration".utf8)
        static let stats = Data("Stats".utf8)
    }
}

/// Per `(service, name, resource, ...)` aggregated stats within a single bucket.
///
/// Field names and order match `ClientGroupedStats.EncodeMsg` in `stats_gen.go`. `okSummary` and
/// `errorSummary` carry the protobuf-encoded DDSketch summaries for the OK and error latency
/// distributions respectively.
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

        encoder.writeRawString(Field.service)
        encoder.writeString(service)

        encoder.writeRawString(Field.name)
        encoder.writeString(name)

        encoder.writeRawString(Field.resource)
        encoder.writeString(resource)

        encoder.writeRawString(Field.httpStatusCode)
        encoder.writeUInt(httpStatusCode)

        encoder.writeRawString(Field.type)
        encoder.writeString(type)

        encoder.writeRawString(Field.hits)
        encoder.writeULong(hits)

        encoder.writeRawString(Field.errors)
        encoder.writeULong(errors)

        encoder.writeRawString(Field.duration)
        encoder.writeULong(duration)

        encoder.writeRawString(Field.okSummary)
        encoder.writeBinary(okSummary)

        encoder.writeRawString(Field.errorSummary)
        encoder.writeBinary(errorSummary)

        encoder.writeRawString(Field.synthetics)
        encoder.writeBoolean(false)

        encoder.writeRawString(Field.topLevelHits)
        encoder.writeULong(topLevelHits)

        encoder.writeRawString(Field.spanKind)
        encoder.writeString(spanKind)

        encoder.writeRawString(Field.peerTags)
        encoder.startArray(elementCount: peerTags.count)
        for tag in peerTags {
            encoder.writeString(tag)
        }

        encoder.writeRawString(Field.isTraceRoot)
        encoder.writeInt(Int32(isTraceRoot.rawValue))

        encoder.writeRawString(Field.grpcStatusCode)
        encoder.writeRawString(Field.emptyString)

        encoder.writeRawString(Field.serviceSource)
        encoder.writeString(serviceSource)
    }

    private enum Field {
        static let groupedStatsFieldCount = 17
        static let service = Data("Service".utf8)
        static let name = Data("Name".utf8)
        static let resource = Data("Resource".utf8)
        static let httpStatusCode = Data("HTTPStatusCode".utf8)
        static let type = Data("Type".utf8)
        static let hits = Data("Hits".utf8)
        static let errors = Data("Errors".utf8)
        static let duration = Data("Duration".utf8)
        static let okSummary = Data("OkSummary".utf8)
        static let errorSummary = Data("ErrorSummary".utf8)
        static let synthetics = Data("Synthetics".utf8)
        static let topLevelHits = Data("TopLevelHits".utf8)
        static let spanKind = Data("SpanKind".utf8)
        static let peerTags = Data("PeerTags".utf8)
        static let isTraceRoot = Data("IsTraceRoot".utf8)
        static let grpcStatusCode = Data("GRPCStatusCode".utf8)
        static let serviceSource = Data("srv_src".utf8)
        static let emptyString = Data()
    }
}
