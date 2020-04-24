/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing

internal struct DDSpanContext: OpenTracing.SpanContext {
    /// This span's trace ID.
    let traceID: TracingUUID
    /// This span ID.
    let spanID: TracingUUID
    /// The ID of the parent span or `nil` if this span is the root span.
    let parentSpanID: TracingUUID?

    // MARK: - Open Tracing interface

    func forEachBaggageItem(callback: (String, String) -> Bool) {
        // TODO: RUMM-292
    }
}
