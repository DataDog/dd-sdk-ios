/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `W3CHTTPHeadersWriter` class facilitates the injection of trace propagation headers into network requests
/// targeted at a backend expecting [W3C propagation format](https://github.com/openzipkin/b3-propagation).
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = W3CHTTPHeadersWriter()
///     let span = Tracer.shared().startRootSpan(operationName: "network request")
///     Tracer.shared().inject(spanContext: span.context, writer: writer)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
public class W3CHTTPHeadersWriter: TracePropagationHeadersWriter {
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
    /// This value will decide of the `FLAG_SAMPLED` header field value
    /// and if `trace-id`, `span-id` are propagated.
    private let sampler: Sampler

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
    public init(sampler: Sampler) {
        self.sampler = sampler
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) {
        typealias Constants = W3CHTTPHeaders.Constants

        let sampled = sampler.sample()

        traceHeaderFields[W3CHTTPHeaders.traceparent] = [
            Constants.version,
            String(traceID, representation: .hexadecimal32Chars),
            String(spanID, representation: .hexadecimal16Chars),
            sampled ? Constants.sampledValue : Constants.unsampledValue
        ]
        .joined(separator: Constants.separator)

        let ddtracestate = [
            "\(Constants.sampling):\(sampled ? 1 : 0)",
            "\(Constants.origin):\(Constants.originRUM)"
        ].joined(separator: Constants.tracestateSeparator)
        traceHeaderFields[W3CHTTPHeaders.tracestate] = "\(Constants.dd)=\(ddtracestate)"
    }
}
