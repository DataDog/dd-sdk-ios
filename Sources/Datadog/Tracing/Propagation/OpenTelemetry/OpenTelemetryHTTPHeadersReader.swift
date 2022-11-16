/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class OpenTelemetryHTTPHeadersReader: OTHTTPHeadersReader {
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

        if let traceIDValue = httpHeaderFields[OpenTelemetryHTTPHeaders.Multiple.traceIDField],
            let spanIDValue = httpHeaderFields[OpenTelemetryHTTPHeaders.Multiple.spanIDField],
            let traceID = UInt64(traceIDValue).flatMap({ TracingUUID(rawValue: $0) }),
            let spanID = UInt64(spanIDValue).flatMap({ TracingUUID(rawValue: $0) }) {
            // TODO Open Telemetry span context
            return DDSpanContext(
                traceID: traceID,
                spanID: spanID,
                parentSpanID: nil,
                baggageItems: BaggageItems(targetQueue: baggageItemQueue, parentSpanItems: nil)
            )
        } else if let b3Value = httpHeaderFields[OpenTelemetryHTTPHeaders.Single.b3Field]?.components(separatedBy: "-"),
            let traceID = b3Value[safe: 0]?.asTracingUUID,
            let spanID = b3Value[safe: 1]?.asTracingUUID {
            return DDSpanContext(
                traceID: traceID,
                spanID: spanID,
                parentSpanID: b3Value[safe: 3]?.asTracingUUID,
                baggageItems: BaggageItems(targetQueue: baggageItemQueue, parentSpanItems: nil)
            )
        }
        return nil
    }
}

private extension Array {
    subscript (safe index: Index) -> Element? {
        0 <= index && index < count ? self[index] : nil
    }
}

private extension String {
    var asTracingUUID: TracingUUID? {
        return UInt64(self).flatMap({ TracingUUID(rawValue: $0) })
    }
}
