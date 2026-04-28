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
internal struct SpanSnapshot: Encodable, Sendable {
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
