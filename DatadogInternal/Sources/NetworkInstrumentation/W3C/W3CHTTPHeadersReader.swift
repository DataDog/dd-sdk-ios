/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class W3CHTTPHeadersReader: TracePropagationHeadersReader {
    private let httpHeaderFields: [String: String]

    public init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    public func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        let values = httpHeaderFields[W3CHTTPHeaders.traceparent]?.components(
            separatedBy: W3CHTTPHeaders.Constants.separator
        )

        guard let traceIDValue = values?[safe: 1],
              let spanIDValue = values?[safe: 2],
              values?[safe: 3] != W3CHTTPHeaders.Constants.unsampledValue,
              let traceID = TraceID(traceIDValue, representation: .hexadecimal),
              let spanID = TraceID(spanIDValue, representation: .hexadecimal)
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
