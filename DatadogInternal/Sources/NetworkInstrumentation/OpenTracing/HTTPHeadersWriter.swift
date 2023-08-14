/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `HTTPHeadersWriter` should be used to inject trace propagation headers to
/// the network requests send to the backend instrumented with Datadog APM.
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = HTTPHeadersWriter()
///     let span = DatadogTracer.shared().startSpan("network request")
///     writer.inject(spanContext: span.context)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
///
public class HTTPHeadersWriter: TracePropagationHeadersWriter {
    /// A dictionary with HTTP Headers required to propagate the trace started in the mobile app
    /// to the backend instrumented with Datadog APM.
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
    private let sampler: Sampler

    /// Creates a `HTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter samplingRate: Tracing sampling rate. 20% by default.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(sampleRate:)` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate)
    }

    public convenience init(sampleRate: Float = 20) {
        self.init(sampler: Sampler(samplingRate: sampleRate))
    }

    /// Creates a `HTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter sampler: Tracing sampler responsible for randomizing the sample.
    public init(sampler: Sampler) {
        self.sampler = sampler
    }

    public func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) {
        let samplingPriority = sampler.sample()

        traceHeaderFields = [
            TracingHTTPHeaders.samplingPriorityField: samplingPriority ? "1" : "0"
        ]

        if samplingPriority {
            traceHeaderFields[TracingHTTPHeaders.traceIDField] = String(traceID)
            traceHeaderFields[TracingHTTPHeaders.parentSpanIDField] = String(spanID)
        }
    }
}
