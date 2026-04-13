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
//    public private(set) var traceHeaderFields: [String: String] = [:]

    public private(set) var traceHeaders: [String: TracePropagationHeaderValue] = [:]

    private let traceContextInjection: TraceContextInjection

    /// Initializes the headers writer.
    ///
    /// - Parameter traceContextInjection: The strategy for injecting trace context into requests.
    public init(traceContextInjection: TraceContextInjection) {
        self.traceContextInjection = traceContextInjection
    }

    /// Writes the trace ID, span ID, and optional parent span ID into the trace propagation headers.
    ///
    /// - Parameter traceID: The trace ID.
    /// - Parameter spanID: The span ID.
    /// - Parameter parentSpanID: The parent span ID, if applicable.
    public func write(traceContext: TraceContext) {
        typealias Constants = W3CHTTPHeaders.Constants

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

        traceHeaders = [
            TracingHTTPHeaders.samplingPriorityField: .string("\(traceContext.samplingPriority.rawValue)")
        ]
        traceHeaders[TracingHTTPHeaders.traceIDField] = .string(String(traceContext.traceID.idLo))
        traceHeaders[TracingHTTPHeaders.parentSpanIDField] = .string(String(traceContext.spanID, representation: .decimal))
        var tags = ["_dd.p.tid": traceContext.traceID.idHiHex]
        if traceContext.samplingPriority.isKept {
            tags["_dd.p.dm"] = traceContext.samplingDecisionMaker.rawValue
        }
        traceHeaders[TracingHTTPHeaders.tagsField] = .keyValueList(.init(values: tags, keyValueSeparator: "=", keyValuePairSeparator: ","))

        var baggageItems: [String: String] = [:]
        if let sessionId = traceContext.rumSessionId {
            baggageItems[W3CHTTPHeaders.Constants.rumSessionBaggageKey] = sessionId
        }
        if let userId = traceContext.userId {
            baggageItems[W3CHTTPHeaders.Constants.userBaggageKey] = userId
        }
        if let accountId = traceContext.accountId {
            baggageItems[W3CHTTPHeaders.Constants.accountBaggageKey] = accountId
        }
        if baggageItems.isEmpty == false {
            traceHeaders[W3CHTTPHeaders.baggage] = .keyValueList(.init(values: baggageItems, keyValueSeparator: "=", keyValuePairSeparator: ","))
        }
    }
}
