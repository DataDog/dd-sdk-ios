/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class OTelHTTPHeadersReader: TracePropagationHeadersReader {
    private let httpHeaderFields: [String: String]

    public init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    public func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        if let traceIDValue = httpHeaderFields[OTelHTTPHeaders.Multiple.traceIDField],
           let spanIDValue = httpHeaderFields[OTelHTTPHeaders.Multiple.spanIDField],
           let traceID = TraceID(traceIDValue, representation: .hexadecimal),
           let spanID = TraceID(spanIDValue, representation: .hexadecimal) {
            return (
                traceID: traceID,
                spanID: spanID,
                parentSpanID: httpHeaderFields[OTelHTTPHeaders.Multiple.parentSpanIDField]
                    .flatMap { TraceID($0, representation: .hexadecimal) }
            )
        }

        let b3Value = httpHeaderFields[OTelHTTPHeaders.Single.b3Field]?
            .components(separatedBy: OTelHTTPHeaders.Constants.b3Separator)

        if let traceIDValue = b3Value?[safe: 0],
           let spanIDValue = b3Value?[safe: 1],
           let traceID = TraceID(traceIDValue, representation: .hexadecimal),
           let spanID = TraceID(spanIDValue, representation: .hexadecimal) {
            return (
                traceID: traceID,
                spanID: spanID,
                parentSpanID: b3Value?[safe: 3].flatMap({ TraceID($0, representation: .hexadecimal) })
            )
        }

        return nil
    }
}
