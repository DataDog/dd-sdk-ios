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

    private let samplingStrategy: TraceSamplingStrategy
    private let traceContextInjection: TraceContextInjection

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(samplingStrategy: .custom(sampleRate:))` instead.")
    public convenience init(sampleRate: Float = 20) {
        self.init(samplingStrategy: .custom(sampleRate: sampleRate), traceContextInjection: .all)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingStrategy: The strategy for sampling trace propagation headers.
    /// - Parameter traceContextInjection: The strategy for injecting trace context into requests.
    public init(
        samplingStrategy: TraceSamplingStrategy,
        traceContextInjection: TraceContextInjection
    ) {
        self.samplingStrategy = samplingStrategy
        self.traceContextInjection = traceContextInjection
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceContext: TraceContext) {
        let sampler = samplingStrategy.sampler(for: traceContext)
        let sampled = sampler.sample()

        switch (traceContextInjection, sampled) {
        case (.all, _), (.sampled, true):
            traceHeaderFields = [
                TracingHTTPHeaders.samplingPriorityField: sampled ? "1" : "0"
            ]
            traceHeaderFields[TracingHTTPHeaders.traceIDField] = String(traceContext.traceID.idLo)
            traceHeaderFields[TracingHTTPHeaders.parentSpanIDField] = String(traceContext.spanID, representation: .decimal)
            traceHeaderFields[TracingHTTPHeaders.tagsField] = "_dd.p.tid=\(traceContext.traceID.idHiHex)"
        case (.sampled, false):
            break
        }
    }
}
