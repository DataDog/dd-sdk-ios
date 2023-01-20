/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Open Telemetry propagation headers as explained in
/// https://github.com/openzipkin/b3-propagation/blob/master/RATIONALE.md
internal enum OTelHTTPHeaders {
    enum Multiple {
        /// The `X-B3-TraceId` header is encoded as 32 or 16 lower-hex characters.
        /// For example, a 128-bit TraceId header might look like: `X-B3-TraceId: 463ac35c9f6413ad48485a3953bb6124`.
        /// Unless propagating only the Sampling State, the `X-B3-TraceId` header is required.
        /// Currently we support 64-bit only.
        static let traceIDField = "X-B3-TraceId"

        /// The `X-B3-SpanId` header is encoded as 16 lower-hex characters.
        /// For example, a SpanId header might look like: `X-B3-SpanId: a2fb4a1d1a96d312`.
        /// Unless propagating only the Sampling State, the `X-B3-SpanId` header is required.
        static let spanIDField = "X-B3-SpanId"

        /// The `X-B3-ParentSpanId` header may be present on a child span and must be absent on the root span.
        /// It is encoded as 16 lower-hex characters.
        /// For example, a ParentSpanId header might look like: `X-B3-ParentSpanId: 0020000000000001`.
        static let parentSpanIDField = "X-B3-ParentSpanId"

        /// An accept sampling decision is encoded as `X-B3-Sampled: 1` and a deny as `X-B3-Sampled: 0`.
        /// Absent means defer the decision to the receiver of this header.
        /// For example, a Sampled header might look like: `X-B3-Sampled: 1`.
        ///
        /// **Note:** Before this specification was written, some tracers propagated `X-B3-Sampled` as true or false as opposed to 1 or 0.
        /// While you shouldn't encode `X-B3-Sampled` as true or false, a lenient implementation may accept them.
        static let sampledField = "X-B3-Sampled"
    }

    enum Single {
        /// A single header named b3 standardized in late 2018 for use in JMS and w3c `tracestate`.
        /// In simplest terms b3 maps propagation fields into a hyphen delimited string.
        /// `b3={TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}`, where the last two fields are optional.
        static let b3Field = "b3"
    }

    enum Constants {
        static let sampledValue = "1"
        static let unsampledValue = "0"
        static let b3Separator = "-"
    }
}
