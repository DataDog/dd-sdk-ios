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

    private let traceContextInjection: TraceContextInjection

    /// Initializes the headers writer.
    ///
    /// - Parameter tracestate: The tracestate to be injected.
    /// - Parameter traceContextInjection: The strategy for injecting trace context into requests.
    public init(
        tracestate: [String: String] = [:],
        traceContextInjection: TraceContextInjection = .sampled
    ) {
        self.tracestate = tracestate
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

        traceHeaderFields[W3CHTTPHeaders.traceparent] = [
            Constants.version,
            String(traceContext.traceID, representation: .hexadecimal32Chars),
            String(traceContext.spanID, representation: .hexadecimal16Chars),
            sampled ? Constants.sampledValue : Constants.unsampledValue
        ]
        .joined(separator: Constants.separator)

        var tracestate: [String: String] = [
            Constants.sampling: "\(traceContext.samplingPriority.rawValue)",
            Constants.parentId: String(traceContext.spanID, representation: .hexadecimal16Chars)
        ]

        if traceContext.samplingPriority.isKept {
            tracestate[Constants.samplingDecisionMaker] = "-\(traceContext.samplingDecisionMaker.rawValue)"
        }

        // while merging, the tracestate values from the tracestate property take precedence
        // over the ones from the trace context
        tracestate.merge(self.tracestate) { old, new in
            return new
        }

        let ddtracestate = tracestate
            .map { "\($0.key)\(Constants.tracestateKeyValueSeparator)\($0.value)" }
            .sorted()
            .joined(separator: Constants.tracestatePairSeparator)

        traceHeaderFields[W3CHTTPHeaders.tracestate] = "\(Constants.dd)=\(ddtracestate)"

        var baggageItems: [String] = []
        if let sessionId = traceContext.rumSessionId {
            baggageItems.append("\(Constants.rumSessionBaggageKey)=\(sessionId)")
        }
        if let userId = traceContext.userId {
            baggageItems.append("\(Constants.userBaggageKey)=\(userId)")
        }
        if let accountId = traceContext.accountId {
            baggageItems.append("\(Constants.accountBaggageKey)=\(accountId)")
        }
        if !baggageItems.isEmpty {
            traceHeaderFields[W3CHTTPHeaders.baggage] = baggageItems.joined(separator: ",")
        }
    }
}
