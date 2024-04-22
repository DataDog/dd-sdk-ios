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

    /// A dictionary containing the tracestate to be injected.
    /// This value will be merged with the tracestate from the trace context.
    private let tracestate: [String: String]

    /// The tracing sampler.
    ///
    /// This value will decide of the `FLAG_SAMPLED` header field value
    /// and if `trace-id`, `span-id` are propagated.
    private let sampler: Sampling

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    /// - Parameter tracestate: The tracestate to be injected.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(sampleRate:)` instead.")
    public convenience init(samplingRate: Float) {
        self.init(sampleRate: samplingRate, tracestate: [:])
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    /// - Parameter tracestate: The tracestate to be injected.
    public convenience init(sampleRate: Float = 20, tracestate: [String: String] = [:]) {
        self.init(sampler: Sampler(samplingRate: sampleRate), tracestate: tracestate)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampler: The sampler used for headers injection.
    /// - Parameter tracestate: The tracestate to be injected.
    public init(sampler: Sampling, tracestate: [String: String]) {
        self.sampler = sampler
        self.tracestate = tracestate
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

        // while merging, the tracestate values from the tracestate property take precedence
        // over the ones from the trace context
        let tracestate: [String: String] = [
            Constants.sampling: "\(sampled ? 1 : 0)",
            Constants.parentId: String(spanID, representation: .hexadecimal16Chars)
        ].merging(tracestate) { old, new in
            return new
        }

        let ddtracestate = tracestate
            .map { "\($0.key)\(Constants.tracestateKeyValueSeparator)\($0.value)" }
            .sorted()
            .joined(separator: Constants.tracestatePairSeparator)

        traceHeaderFields[W3CHTTPHeaders.tracestate] = "\(Constants.dd)=\(ddtracestate)"
    }
}
