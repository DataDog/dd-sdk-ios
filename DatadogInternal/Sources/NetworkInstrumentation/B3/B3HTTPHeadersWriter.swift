/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@available(*, deprecated, renamed: "B3HTTPHeadersWriter")
public typealias OTelHTTPHeadersWriter = B3HTTPHeadersWriter

/// The `B3HTTPHeadersWriter` class facilitates the injection of trace propagation headers into network requests
/// targeted at a backend expecting [B3 propagation format](https://github.com/openzipkin/b3-propagation).
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = B3HTTPHeadersWriter(injectEncoding: .single)
///     let span = Tracer.shared().startRootSpan(operationName: "network request")
///     Tracer.shared().inject(spanContext: span.context, writer: writer)
///
///     writer.traceHeaderFields.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
public class B3HTTPHeadersWriter: TracePropagationHeadersWriter {
    /// Enumerates B3 header encoding options.
    ///
    /// There are two encodings of B3 propagation:
    /// [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
    /// and [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
    ///
    /// Multiple header encoding employs an `X-B3-` prefixed header per item in the trace context.
    /// Single header delimits the context into a single entry named `B3`.
    /// The single-header variant takes precedence over the multiple header one when extracting fields.
    public enum InjectEncoding {
        /// Encoding that employs `X-B3-*` prefixed headers per item in the trace context.
        ///
        /// See: [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
        case multiple
        /// Encoding that uses a single `B3` header to transport the trace context.
        ///
        /// See: [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
        case single
    }

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
    /// The sample rate determines the `X-B3-Sampled` header field value
    /// and whether `X-B3-TraceId`, `X-B3-SpanId`, and `X-B3-ParentSpanId` are propagated.
    private let sampler: Sampling

    /// The telemetry header encoding used by the writer.
    private let injectEncoding: InjectEncoding

    /// Initializes the headers writer.
    ///
    /// - Parameter samplingRate: The sampling rate applied for headers injection.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    @available(*, deprecated, message: "This will be removed in future versions of the SDK. Use `init(sampleRate:injectEncoding:)` instead.")
    public convenience init(
        samplingRate: Float,
        injectEncoding: InjectEncoding = .single
    ) {
        self.init(sampleRate: samplingRate, injectEncoding: injectEncoding)
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampleRate: The sampling rate applied for headers injection, with 20% as the default.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    public convenience init(
        sampleRate: Float = 20,
        injectEncoding: InjectEncoding = .single
    ) {
        self.init(
            sampler: Sampler(samplingRate: sampleRate),
            injectEncoding: injectEncoding
        )
    }

    /// Initializes the headers writer.
    ///
    /// - Parameter sampler: The sampler used for headers injection.
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    public init(
        sampler: Sampling,
        injectEncoding: InjectEncoding = .single
    ) {
        self.sampler = sampler
        self.injectEncoding = injectEncoding
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) {
        let samplingPriority = sampler.sample()

        typealias Constants = B3HTTPHeaders.Constants

        switch injectEncoding {
        case .multiple:
            traceHeaderFields = [
                B3HTTPHeaders.Multiple.sampledField: samplingPriority ? Constants.sampledValue : Constants.unsampledValue
            ]

            if samplingPriority {
                traceHeaderFields[B3HTTPHeaders.Multiple.traceIDField] = String(traceID, representation: .hexadecimal32Chars)
                traceHeaderFields[B3HTTPHeaders.Multiple.spanIDField] = String(spanID, representation: .hexadecimal16Chars)
                traceHeaderFields[B3HTTPHeaders.Multiple.parentSpanIDField] = parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
            }
        case .single:
            if samplingPriority {
                traceHeaderFields[B3HTTPHeaders.Single.b3Field] = [
                    String(traceID, representation: .hexadecimal32Chars),
                    String(spanID, representation: .hexadecimal16Chars),
                    samplingPriority ? Constants.sampledValue : Constants.unsampledValue,
                    parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
                ]
                .compactMap { $0 }
                .joined(separator: Constants.b3Separator)
            } else {
                traceHeaderFields[B3HTTPHeaders.Single.b3Field] = Constants.unsampledValue
            }
        }
    }
}
