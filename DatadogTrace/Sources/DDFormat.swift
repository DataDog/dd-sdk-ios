/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension HTTPHeadersReader: OTFormatReader {}
extension W3CHTTPHeadersReader: OTFormatReader {}
extension B3HTTPHeadersReader: OTFormatReader {}

extension HTTPHeadersWriter: OTFormatWriter {}
extension W3CHTTPHeadersWriter: OTFormatWriter {}
extension B3HTTPHeadersWriter: OTFormatWriter {}

extension TracePropagationHeadersWriter where Self: OTFormatWriter {
    public func inject(spanContext: OTSpanContext) {
        guard let spanContext = spanContext.dd else {
            return
        }

        write(
            traceID: spanContext.traceID,
            spanID: spanContext.spanID,
            parentSpanID: spanContext.parentSpanID
        )
    }
}

extension TracePropagationHeadersReader where Self: OTFormatReader {
    public func extract() -> OTSpanContext? {
        guard let ids = read() else {
            return nil
        }
        return DDSpanContext(
            traceID: ids.traceID,
            spanID: ids.spanID,
            parentSpanID: ids.parentSpanID,
            baggageItems: BaggageItems(),
            sampleRate: tracerSampleRate ?? 0, // unreachable default: sample rate is set by the tracer during extraction
            isKept: sampled ?? false // unreachable default: we got trace ID, so this request must have been instrumented
        )
    }
}
