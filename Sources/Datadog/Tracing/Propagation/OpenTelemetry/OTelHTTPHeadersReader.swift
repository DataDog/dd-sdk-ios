/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class OTelHTTPHeadersReader: OTHTTPHeadersReader, TracePropagationHeadersExtractor {
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

        if let traceIDValue = httpHeaderFields[OTelHTTPHeaders.Multiple.traceIDField],
            let spanIDValue = httpHeaderFields[OTelHTTPHeaders.Multiple.spanIDField],
            let traceID = TracingUUID(traceIDValue, .hexadecimal),
            let spanID = TracingUUID(spanIDValue, .hexadecimal) {
            return DDSpanContext(
                traceID: traceID,
                spanID: spanID,
                parentSpanID: TracingUUID(httpHeaderFields[OTelHTTPHeaders.Multiple.parentSpanIDField], .hexadecimal),
                baggageItems: BaggageItems(targetQueue: baggageItemQueue, parentSpanItems: nil)
            )
        } else if let b3Value = httpHeaderFields[OTelHTTPHeaders.Single.b3Field]?.components(
                separatedBy: OTelHTTPHeaders.Constants.b3Separator
            ),
            let traceID = TracingUUID(b3Value[safe: 0], .hexadecimal),
            let spanID = TracingUUID(b3Value[safe: 1], .hexadecimal) {
            return DDSpanContext(
                traceID: traceID,
                spanID: spanID,
                parentSpanID: TracingUUID(b3Value[safe: 3], .hexadecimal),
                baggageItems: BaggageItems(targetQueue: baggageItemQueue, parentSpanItems: nil)
            )
        }
        return nil
    }
}
