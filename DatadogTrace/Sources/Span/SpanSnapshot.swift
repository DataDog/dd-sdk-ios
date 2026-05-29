/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Nanosecond-precision time value used across client-side stats.
internal typealias Nanoseconds = UInt64

/// A lightweight, immutable snapshot of span data needed for client-side stats computation.
///
/// Created in `DDSpan.finish()` **before** the sampling decision, so that all spans
/// (including sampled-out ones) contribute to accurate aggregate metrics.
///
/// The snapshot is derived from a post-`SpanEventMapper` `SpanEvent`, which guarantees
/// that stats and trace uploads agree on resource name, service name, tags, and the
/// `isError` flag. Without this, a customer-supplied mapper that rewrites resource
/// names (e.g. to redact PII or normalize cardinality) would key stats off the
/// pre-mapper values while traces carry post-mapper values, leading to dashboard
/// inconsistencies and potential cardinality explosions in the stats pipeline.
internal struct SpanSnapshot: Encodable, Sendable {
    /// Span tag keys that participate in peer-service aggregation. Mirrors the
    /// `peer_tags_aggregation` set used by the Datadog Agent.
    static let peerTagKeys: [String] = [
        "peer.service",
        "db.instance",
        "db.system",
        "out.host",
        "net.peer.name",
        "server.address"
    ]

    let traceID: TraceID
    let spanID: SpanID
    let parentSpanID: SpanID?
    var service: String
    let operationName: String
    let resource: String
    /// Span type (e.g. `"custom"`, `"http"`, `"web"`).
    let type: String
    let spanKind: String?
    let httpStatusCode: UInt32
    let isError: Bool
    /// Span start time in nanoseconds since Unix epoch.
    let startTime: Nanoseconds
    /// Span duration in nanoseconds.
    let duration: Nanoseconds
    let isTopLevel: Bool
    let isMeasured: Bool
    /// Peer tag values for downstream-service aggregation (e.g. `peer.service`, `out.host`).
    let peerTags: [String: String]
    /// The source of the service name override, from `_dd.svc_src` span meta tag.
    let serviceSource: String
}

extension SpanSnapshot {
    /// Creates a snapshot from a post-mapper `SpanEvent`.
    ///
    /// All fields are read from the event (and its `tags`), so any mutation applied by
    /// the user-configured `SpanEventMapper` is reflected in the stats aggregation.
    init(from event: SpanEvent) {
        let spanKind = event.tags[SpanTags.kind]
        let httpStatusCode: UInt32 = {
            guard let raw = event.tags[OTTags.httpStatusCode],
                  let intValue = Int(raw),
                  let uint32 = UInt32(exactly: intValue) else {
                return 0
            }
            return uint32
        }()
        let isTopLevel = event.parentID == nil || event.tags["_dd.top_level"] == "1"
        let isMeasured = event.tags["_dd.measured"] == "1"
        let serviceSource = event.tags["_dd.svc_src"] ?? ""

        var peerTags: [String: String] = [:]
        for key in SpanSnapshot.peerTagKeys {
            if let value = event.tags[key], !value.isEmpty {
                peerTags[key] = value
            }
        }

        self.init(
            traceID: event.traceID,
            spanID: event.spanID,
            parentSpanID: event.parentID,
            service: event.serviceName,
            operationName: event.operationName,
            resource: event.resource,
            type: event.tags["span.type"] ?? "custom",
            spanKind: spanKind,
            httpStatusCode: httpStatusCode,
            isError: event.isError,
            startTime: event.startTime.timeIntervalSince1970.dd.toNanoseconds,
            duration: event.duration.dd.toNanoseconds,
            isTopLevel: isTopLevel,
            isMeasured: isMeasured,
            peerTags: peerTags,
            serviceSource: serviceSource
        )
    }
}
