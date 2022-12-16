/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class W3CHTTPHeadersReader: OTHTTPHeadersReader, TracePropagationHeadersExtractor {
    private let httpHeaderFields: [String: String]
    private var baggageItemQueue: DispatchQueue?

    init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    func use(baggageItemQueue: DispatchQueue) {
        self.baggageItemQueue = baggageItemQueue
    }

    func extract() -> OTSpanContext? {
        guard let baggageItemQueue = baggageItemQueue else {
            return nil
        }

        guard let traceparentValue = httpHeaderFields[W3CHTTPHeaders.traceparent]?.components(
                separatedBy: W3CHTTPHeaders.Constants.separator
            ),
            let traceID = TracingUUID(traceparentValue[safe: 1], .hexadecimal),
            let spanID = TracingUUID(traceparentValue[safe: 2], .hexadecimal),
            traceparentValue[safe: 3] != W3CHTTPHeaders.Constants.unsampledValue else {
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
