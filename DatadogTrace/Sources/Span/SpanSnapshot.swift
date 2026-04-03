/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A lightweight, immutable snapshot of a `DDSpan` at the moment it finishes.
///
/// Created in `DDSpan.finish(at:)` **before** the sampling decision so that
/// every finished span — including sampled-out ones — can be forwarded to the
/// `StatsConcentrator` for client-side stats computation.
///
/// The snapshot captures only the data needed for stats aggregation, avoiding
/// any reference back to the mutable `DDSpan`.
internal struct SpanSnapshot {
    let traceID: TraceID
    let spanID: SpanID
    let parentSpanID: SpanID?
    let service: String
    let operationName: String
    let resource: String
    let type: String
    let spanKind: String?
    let httpStatusCode: UInt32
    let isError: Bool
    /// Span start time in nanoseconds since Unix epoch.
    let startTime: UInt64
    /// Span duration in nanoseconds.
    let duration: UInt64
    let isTopLevel: Bool
    let isMeasured: Bool
    /// Peer tag values for downstream-service aggregation (e.g., `peer.service`, `out.host`).
    let peerTags: [String: String]
    let isSynthetics: Bool
    /// Value of `_dd.svc_src` meta tag, if present. Tracks the origin of the service name.
    let serviceSource: String?
}
