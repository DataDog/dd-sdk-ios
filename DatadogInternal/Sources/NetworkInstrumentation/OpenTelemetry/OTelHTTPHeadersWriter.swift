/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `OTelHTTPHeadersWriter` should be used to inject trace propagation headers to
/// the network requests send to the backend instrumented with Open Telemetry.
/// The injected headers conform to [Open Telemetry](https://github.com/openzipkin/b3-propagation) standard.
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = OTelHTTPHeadersWriter(injectEncoding: .single)
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
public class OTelHTTPHeadersWriter: TracePropagationHeadersWriter {
    /// Open Telemetry header encoding.
    ///
    /// There are two encodings of B3:
    /// [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
    /// and [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
    ///
    /// Multiple header encoding uses an `X-B3-` prefixed header per item in the trace context.
    /// Single header delimits the context into into a single entry named b3.
    /// The single-header variant takes precedence over the multiple header one when extracting fields.
    public enum InjectEncoding {
        case multiple, single
    }

    /// A dictionary with HTTP Headers required to propagate the trace started in the mobile app
    /// to the backend instrumented with Open Telemetry.
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
    /// This value will decide of the `X-B3-Sampled` header field value
    /// and if `X-B3-TraceId`, `X-B3-SpanId` and `X-B3-ParentSpanId` are propagated.
    private let sampler: Sampler

    /// Determines the type of telemetry header type used by the writer.
    private let injectEncoding: InjectEncoding

    /// Creates a `OTelHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter samplingRate: Tracing sampling rate. 20% by default.
    /// - Parameter injectEncoding: Determines the type of telemetry header type used by the writer.
    public init(
        samplingRate: Float = 20,
        injectEncoding: InjectEncoding = .single
    ) {
        self.sampler = Sampler(samplingRate: samplingRate)
        self.injectEncoding = injectEncoding
    }

    /// Creates a `OTelHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter sampler: Tracing sampler responsible for randomizing the sample.
    /// - Parameter injectEncoding: Determines the type of telemetry header type used by the writer.
    public init(
        sampler: Sampler,
        injectEncoding: InjectEncoding = .single
    ) {
        self.sampler = sampler
        self.injectEncoding = injectEncoding
    }

    public func write(traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) {
        let samplingPriority = sampler.sample()

        typealias Constants = OTelHTTPHeaders.Constants

        switch injectEncoding {
        case .multiple:
            traceHeaderFields = [
                OTelHTTPHeaders.Multiple.sampledField: samplingPriority ? Constants.sampledValue : Constants.unsampledValue
            ]

            if samplingPriority {
                traceHeaderFields[OTelHTTPHeaders.Multiple.traceIDField] = String(traceID, representation: .hexadecimal32Chars)
                traceHeaderFields[OTelHTTPHeaders.Multiple.spanIDField] = String(spanID, representation: .hexadecimal16Chars)
                traceHeaderFields[OTelHTTPHeaders.Multiple.parentSpanIDField] = parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
            }
        case .single:
            if samplingPriority {
                traceHeaderFields[OTelHTTPHeaders.Single.b3Field] = [
                    String(traceID, representation: .hexadecimal32Chars),
                    String(spanID, representation: .hexadecimal16Chars),
                    samplingPriority ? Constants.sampledValue : Constants.unsampledValue,
                    parentSpanID.map { String($0, representation: .hexadecimal16Chars) }
                ]
                .compactMap { $0 }
                .joined(separator: Constants.b3Separator)
            } else {
                traceHeaderFields[OTelHTTPHeaders.Single.b3Field] = Constants.unsampledValue
            }
        }
    }
}
