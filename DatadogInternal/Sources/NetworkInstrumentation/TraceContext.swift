/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A context used to propagate trace through HTTP request headers.
public struct TraceContext: Equatable {
    /// The unique identifier for the trace.
    public let traceID: TraceID
    /// The unique identifier for the span.
    public let spanID: SpanID
    /// The unique identifier for the parent span, if any.
    public let parentSpanID: SpanID?
    /// The sample rate used for injecting the span into a request.
    ///
    /// It is a value between `0.0` (drop) and `100.0` (keep), determined by the local or distributed trace sampler.
    public let sampleRate: Float
    /// Indicates whether this span was sampled or rejected by the sampler.
    public let isKept: Bool

    /// The unique identifier for the current RUM Session, if any.
    public let rumSessionId: String?

    /// Initializes a `TraceContext` instance with the provided parameters.
    ///
    /// - Parameters:
    ///   - traceID: The unique identifier for the trace.
    ///   - spanID: The unique identifier for the span.
    ///   - parentSpanID: The unique identifier for the parent span, if any.
    ///   - sampleRate: The sample rate used for injecting the span into a request.
    ///   - isKept: A boolean indicating whether this span was sampled or rejected by the sampler.
    public init(
        traceID: TraceID,
        spanID: SpanID,
        parentSpanID: SpanID?,
        sampleRate: Float,
        isKept: Bool,
        rumSessionId: String?
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.sampleRate = sampleRate
        self.isKept = isKept
        self.rumSessionId = rumSessionId
    }
}
