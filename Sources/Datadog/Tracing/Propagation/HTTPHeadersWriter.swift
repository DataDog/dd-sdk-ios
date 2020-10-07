/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
public class HTTPHeadersWriter: OTHTTPHeadersWriter {
    public init() {}

    /// A dictionary with HTTP Headers required to propagate the trace started in the mobile app
    /// to the backend instrumented with Datadog APM.
    ///
    /// Usage:
    ///
    ///     writer.tracePropagationHTTPHeaders.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var tracePropagationHTTPHeaders: [String: String] = [:]

    public func inject(spanContext: OTSpanContext) {
        guard let spanContext = spanContext.dd else {
            return
        }

        tracePropagationHTTPHeaders = [
            TracingHTTPHeaders.traceIDField: String(spanContext.traceID.rawValue),
            TracingHTTPHeaders.parentSpanIDField: String(spanContext.spanID.rawValue)
        ]
    }
}
