/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public class HTTPHeadersWriter: OTHTTPHeadersWriter {
    private enum Constants: String, CaseIterable {
        case traceIDField = "x-datadog-trace-id"
        case parentSpanIDField = "x-datadog-parent-id"
        // TODO: RUMM-338 support `x-datadog-sampling-priority`. `dd-trace-ot` reference:
        // https://github.com/DataDog/dd-trace-java/blob/4ba0ca0f9da748d4018310d026b1a72b607947f1/dd-trace-ot/src/main/java/datadog/opentracing/propagation/DatadogHttpCodec.java#L23
    }

    public init() {}

    /// The `tracePropagationHTTPHeaders` will be used by customers to add additional headers to the
    /// `URLRequest` in order to propagate the trace to Datadog-OT-instrumented backend.
    ///
    /// TODO: revisit in RUMM-386
    public private(set) var tracePropagationHTTPHeaders: [String: String] = [:]

    public func inject(spanContext: OTSpanContext) {
        guard let spanContext = spanContext.dd else {
            return
        }

        tracePropagationHTTPHeaders = [
            Constants.traceIDField.rawValue: String(spanContext.traceID.rawValue),
            Constants.parentSpanIDField.rawValue: String(spanContext.spanID.rawValue)
        ]
    }

    internal static func canInject(to request: URLRequest) -> Bool {
        let containsHeaders: Bool
        containsHeaders = Constants.allCases.contains { headerKey -> Bool in
            return request.value(forHTTPHeaderField: headerKey.rawValue) != nil
        }
        return !containsHeaders
    }
}
