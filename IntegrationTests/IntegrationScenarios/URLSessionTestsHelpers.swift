/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import HTTPServerMock

protocol URLSessionTestsHelpers {
    func getTraceID(from request: Request) -> TraceID?

    func getSpanID(from request: Request) -> SpanID?

    func isValid(sampleRate: Double) -> Bool

    func getRequestTags(_ request: Request) -> [String : String]
}

extension URLSessionTestsHelpers {
    func getTraceID(from request: Request) -> TraceID? {
        guard let traceIDLoValue = request.httpHeaders["x-datadog-trace-id"] else {
            return nil
        }

        let tags = getRequestTags(request)
        let traceIDHiValue = tags[TracingHTTPHeaders.TagKeys.traceIDHi] ?? "0"

        return .init(
            idHi: UInt64(traceIDHiValue, radix: 16) ?? 0,
            idLo: UInt64(traceIDLoValue, radix: 10) ?? 0
        )
    }

    func getSpanID(from request: Request) -> SpanID? {
        guard let spanId = request.httpHeaders["x-datadog-parent-id"] else {
            return nil
        }
        return .init(spanId, representation: .decimal)
    }

    func isValid(sampleRate: Double) -> Bool { sampleRate >= 0 && sampleRate <= 1 }

    func getRequestTags(_ request: Request) -> [String : String] {
        // tags are comma separated key=value pairs
        return request.httpHeaders[TracingHTTPHeaders.tagsField]?.split(separator: ",")
            .map { $0.split(separator: "=") }
            .reduce(into: [String: String]()) { result, pair in
                if pair.count == 2 {
                    result[String(pair[0])] = String(pair[1])
                }
            } ?? [:]
    }
}
