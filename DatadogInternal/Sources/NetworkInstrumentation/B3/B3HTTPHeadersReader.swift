/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class B3HTTPHeadersReader: TracePropagationHeadersReader {
    private let httpHeaderFields: [String: String]

    public init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    public func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        if let traceIDValue = httpHeaderFields[B3HTTPHeaders.Multiple.traceIDField],
           let spanIDValue = httpHeaderFields[B3HTTPHeaders.Multiple.spanIDField],
           let traceID = TraceID(traceIDValue, representation: .hexadecimal),
           let spanID = SpanID(spanIDValue, representation: .hexadecimal) {
            return (
                traceID: traceID,
                spanID: spanID,
                parentSpanID: httpHeaderFields[B3HTTPHeaders.Multiple.parentSpanIDField]
                    .flatMap { SpanID($0, representation: .hexadecimal) }
            )
        }

        let b3Value = httpHeaderFields[B3HTTPHeaders.Single.b3Field]?
            .components(separatedBy: B3HTTPHeaders.Constants.b3Separator)

        if let traceIDValue = b3Value?[safe: 0],
           let spanIDValue = b3Value?[safe: 1],
           let traceID = TraceID(traceIDValue, representation: .hexadecimal),
           let spanID = SpanID(spanIDValue, representation: .hexadecimal) {
            return (
                traceID: traceID,
                spanID: spanID,
                parentSpanID: b3Value?[safe: 3].flatMap({ SpanID($0, representation: .hexadecimal) })
            )
        }

        return nil
    }

    public var sampled: Bool? {
        if let single = httpHeaderFields[B3HTTPHeaders.Single.b3Field] {
            return single != B3HTTPHeaders.Constants.unsampledValue
        } else if let multiple = httpHeaderFields[B3HTTPHeaders.Multiple.sampledField] {
            return multiple == B3HTTPHeaders.Constants.sampledValue
        }

        return nil
    }
}
