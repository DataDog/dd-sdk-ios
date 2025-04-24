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
            traceContext: TraceContext(
                traceID: spanContext.traceID,
                spanID: spanContext.spanID,
                parentSpanID: spanContext.parentSpanID,
                sampleRate: spanContext.sampleRate,
                isKept: spanContext.isKept,
                rumSessionId: nil
            )
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
            // RUM-3470: The `0` sample rate set here is only a placeholder value. It is overwritten with
            // the actual value in the caller: `Tracer.extract(reader)`.
            sampleRate: 0,
            // RUM-3470: The `false` default will be never reached. As we got trace and span ID,
            // it means that the request has been instrumented, so sampling decision was read as well.
            isKept: sampled ?? false
        )
    }
}
