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
        guard let traceIDValue = httpHeaderFields[TracingHTTPHeaders.traceIDField],
              let spanIDValue = httpHeaderFields[TracingHTTPHeaders.parentSpanIDField],
              let traceID = TraceID(traceIDValue, representation: .hexadecimal),
              let spanID = SpanID(spanIDValue, representation: .hexadecimal)
        else {
            return nil
        }

        return (
            traceID: traceID,
            spanID: spanID,
            parentSpanID: nil
        )
    }
}
