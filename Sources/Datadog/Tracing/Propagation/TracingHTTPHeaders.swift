/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct TracingHTTPHeaders {
    static let traceIDField = "x-datadog-trace-id"
    static let parentSpanIDField = "x-datadog-parent-id"
    // TODO: RUMM-338 support `x-datadog-sampling-priority`. `dd-trace-ot` reference:
    // https://github.com/DataDog/dd-trace-java/blob/4ba0ca0f9da748d4018310d026b1a72b607947f1/dd-trace-ot/src/main/java/datadog/opentracing/propagation/DatadogHttpCodec.java#L23
}
