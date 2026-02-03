/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

// TODO: RUM-13222 OpenTelemetryApi.SpanContext is *definitely* not sendable. Since we're not adding a new problem, it already existed, marking it as @unchecked for now.
/// Represents a span link containing a `SpanContext` and additional attributes.
internal struct OTelSpanLink: Equatable, @unchecked Sendable {
    /// Context of the linked span.
    let context: OpenTelemetryApi.SpanContext

    /// Additional attributes of the linked span.
    let attributes: [String: OpenTelemetryApi.AttributeValue]
}

extension OTelSpanLink: Encodable {
    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
        case attributes = "attributes"
        case traceState = "tracestate"
        case traceFlags = "flags"
    }

    /// Encodes the span link to the following JSON format:
    /// ```json
    ///  {
    ///     "trace_id": "<exactly 32 character, zero-padded lower-case hexadecimal encoded trace id>",
    ///     "span_id": "<exactly 16 character, zero-padded lower-case hexadecimal encoded span id>",
    ///     "attributes": {"key":"value", "pairs":"of", "arbitrary":"values"},
    ///     "dropped_attributes_count": <decimal 64 bit integer>,
    ///     "tracestate": "a tracestate as defined in the W3C standard",
    ///     "flags": <an integer representing the flags as defined in the W3C standard>
    /// },
    /// ```
    /// - Parameter encoder: Encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let traceId = String(context.traceId.toDatadog(), representation: .hexadecimal32Chars)

        try container.encode(traceId, forKey: .traceId)
        try container.encode(context.spanId.hexString, forKey: .spanId)
        if !attributes.isEmpty {
            try container.encode(attributes.tags, forKey: .attributes)
        }

        if !context.traceState.entries.isEmpty {
            try container.encode(context.traceState.w3c(), forKey: .traceState)
        }
        try container.encode(context.traceFlags.byte, forKey: .traceFlags)
    }
}
