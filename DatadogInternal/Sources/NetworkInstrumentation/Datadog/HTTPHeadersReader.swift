/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class HTTPHeadersReader: TracePropagationHeadersReader {
    private let httpHeaderFields: [String: String]

    public init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    public func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        guard let traceIDLoValue = httpHeaderFields[TracingHTTPHeaders.traceIDField],
              let spanIDValue = httpHeaderFields[TracingHTTPHeaders.parentSpanIDField],
              let spanID = SpanID(spanIDValue, representation: .hexadecimal)
        else {
            return nil
        }

        // tags are comma separated key=value pairs
        let tags = httpHeaderFields[TracingHTTPHeaders.tagsField]?.split(separator: ",")
            .map { $0.split(separator: "=") }
            .reduce(into: [String: String]()) { result, pair in
                if pair.count == 2 {
                    result[String(pair[0])] = String(pair[1])
                }
            } ?? [:]

        let traceIDHiValue = tags[TracingHTTPHeaders.TagKeys.traceIDHi] ?? "0"

        let traceID = TraceID(
            idHi: UInt64(traceIDHiValue, radix: 16) ?? 0,
            idLo: UInt64(traceIDLoValue, radix: 16) ?? 0
        )

        return (
            traceID: traceID,
            spanID: spanID,
            parentSpanID: nil
        )
    }

    public var sampled: Bool? {
        if let sampling = httpHeaderFields[TracingHTTPHeaders.samplingPriorityField] {
            return sampling == "1"
        }
        return nil
    }
}
