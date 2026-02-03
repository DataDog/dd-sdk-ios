/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

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

    /// Defines whether the trace context should be injected into all requests or only sampled ones.
    private let traceContextInjection: TraceContextInjection

    /// The telemetry header encoding used by the writer.
    private let injectEncoding: InjectEncoding

    /// Initializes the headers writer.
    ///
    /// - Parameter injectEncoding: The B3 header encoding type, with `.single` as the default.
    /// - Parameter traceContextInjection: The trace context injection strategy, with `.sampled` as the default.
    public init(
        injectEncoding: InjectEncoding = .single,
        traceContextInjection: TraceContextInjection = .sampled
    ) {
        self.injectEncoding = injectEncoding
        self.traceContextInjection = traceContextInjection
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceContext: TraceContext) {
        typealias Constants = B3HTTPHeaders.Constants

        let sampled = traceContext.samplingPriority.isKept
        let shouldInject: Bool = {
            switch traceContextInjection {
            case .all:      return true
            case .sampled:  return sampled
            }
        }()
        guard shouldInject else {
            return
        }

        switch injectEncoding {
        case .multiple:
            traceHeaderFields = [
                B3HTTPHeaders.Multiple.sampledField: sampled ? Constants.sampledValue : Constants.unsampledValue,
                B3HTTPHeaders.Multiple.traceIDField: String(traceContext.traceID, representation: .hexadecimal32Chars),
                B3HTTPHeaders.Multiple.spanIDField: String(traceContext.spanID, representation: .hexadecimal16Chars),
            ]
            if let parentSpanId = traceContext.parentSpanID.map({ String($0, representation: .hexadecimal16Chars) }) {
                traceHeaderFields[B3HTTPHeaders.Multiple.parentSpanIDField] = parentSpanId
            }
        case .single:
            traceHeaderFields[B3HTTPHeaders.Single.b3Field] = [
                String(traceContext.traceID, representation: .hexadecimal32Chars),
                String(traceContext.spanID, representation: .hexadecimal16Chars),
                sampled ? Constants.sampledValue : Constants.unsampledValue,
                traceContext.parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
            ]
            .compactMap { $0 }
            .joined(separator: Constants.b3Separator)
        }
    }
}
