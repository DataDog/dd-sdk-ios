/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `HTTPHeadersWriter` class facilitates the injection of trace propagation headers into network requests
/// targeted at a backend instrumented with Datadog and expecting `x-datadog-*` headers.
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = HTTPHeadersWriter()
///     let span = Tracer.shared().startRootSpan(operationName: "network request")
///     Tracer.shared().inject(spanContext: span.context, writer: writer)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
public class HTTPHeadersWriter: TracePropagationHeadersWriter {
    /// A dictionary containing the required HTTP Headers for propagating trace information.
    ///
    /// Usage:
    ///
    ///     writer.traceHeaderFields.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var traceHeaderFields: [String: String] = [:]

    /// The tracing sampler.
    ///
    /// This value will decide of the `x-datadog-sampling-priority` header field value
    /// and if `x-datadog-trace-id` and `x-datadog-parent-id` are propagated.
    private let sampler: Sampling

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(sampleRate:)` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    public convenience init(sampleRate: Float = 20) {
        self.init(sampler: Sampler(samplingRate: sampleRate))
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampler: The sampler used for headers injection.
    public init(sampler: Sampling) {
        self.sampler = sampler
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) {
        let samplingPriority = sampler.sample()

        traceHeaderFields = [
            TracingHTTPHeaders.samplingPriorityField: samplingPriority ? "1" : "0"
        ]

        if samplingPriority {
            traceHeaderFields[TracingHTTPHeaders.traceIDField] = traceID.idLoHex
            traceHeaderFields[TracingHTTPHeaders.parentSpanIDField] = String(spanID, representation: .hexadecimal)
            traceHeaderFields[TracingHTTPHeaders.tagsField] = "_dd.p.tid=\(traceID.idHiHex)"
        }
    }
}
