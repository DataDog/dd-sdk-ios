/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class HTTPHeadersReader: OTHTTPHeadersReader, TracePropagationHeadersExtractor {
    private let httpHeaderFields: [String: String]
    private var baggageItemQueue: DispatchQueue?

    init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    func use(baggageItemQueue: DispatchQueue) {
        self.baggageItemQueue = baggageItemQueue
    }

    func extract() -> OTSpanContext? {
        guard let baggageItemQueue = baggageItemQueue,
              let traceIDValue = httpHeaderFields[TracingHTTPHeaders.traceIDField],
              let spanIDValue = httpHeaderFields[TracingHTTPHeaders.parentSpanIDField],
              let traceID = TracingUUID(traceIDValue, .decimal),
              let spanID = TracingUUID(spanIDValue, .decimal) else {
            return nil
        }

        return DDSpanContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: nil,
            baggageItems: BaggageItems(targetQueue: baggageItemQueue, parentSpanItems: nil)
        )
    }
}
