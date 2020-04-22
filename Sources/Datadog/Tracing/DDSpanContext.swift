/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing

internal struct DDSpanContext: SpanContext {
    let traceID: TracingUUID
    let spanID: TracingUUID

    // MARK: - Open Tracing interface

    func forEachBaggageItem(callback: (String, String) -> Bool) {
        // TODO: RUMM-292
    }
}
