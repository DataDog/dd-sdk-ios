/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `W3CHTTPHeadersWriter` should be used to inject trace propagation headers to
/// the network requests send to the backend instrumented with W3C trace context.
/// The injected headers conform to [W3C](https://www.w3.org/TR/trace-context/) standard.
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = W3CHTTPHeadersWriter()
///     let span = Global.sharedTracer.startSpan("network request")
///     writer.inject(spanContext: span.context)
///
///     writer.tracePropagationHTTPHeaders.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
///
public class W3CHTTPHeadersWriter: OTHTTPHeadersWriter, TracePropagationHeadersProvider {
    /// A dictionary with HTTP Headers required to propagate the trace started in the mobile app
    /// to the backend instrumented with W3C trace context.
    ///
    /// Usage:
    ///
    ///     writer.tracePropagationHTTPHeaders.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var tracePropagationHTTPHeaders: [String: String] = [:]

    /// The tracing sampler.
    ///
    /// This value will decide of the `FLAG_SAMPLED` header field value
    /// and if `trace-id`, `span-id` are propagated.
    private let sampler: Sampler

    /// Creates a `W3CHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter samplingRate: Tracing sampling rate. 20% by default.
    public init(
        samplingRate: Float = 20
    ) {
        self.sampler = Sampler(samplingRate: samplingRate)
    }

    /// Creates a `W3CHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter sampler: Tracing sampler responsible for randomizing the sample.
    internal init(
        sampler: Sampler
    ) {
        self.sampler = sampler
    }

    public func inject(spanContext: OTSpanContext) {
        guard let spanContext = spanContext.dd else {
            return
        }

        let samplingPriority = sampler.sample()

        typealias Constants = W3CHTTPHeaders.Constants

        tracePropagationHTTPHeaders[W3CHTTPHeaders.traceparent] = [
            Constants.version,
            spanContext.traceID.toString(.hexadecimal32Chars),
            spanContext.spanID.toString(.hexadecimal16Chars),
            samplingPriority ? Constants.sampledValue : Constants.unsampledValue
        ]
        .joined(separator: Constants.separator)
    }
}
