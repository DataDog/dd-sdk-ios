/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct TracingUUID: Equatable {
    /// The unique integer (64-bit unsigned) ID of the trace containing this span.
    /// - See also: [Datadog API Reference - Send Traces](https://docs.datadoghq.com/api/?lang=bash#send-traces)
    let rawValue: UInt64

    static func generateUnique() -> TracingUUID {
        // TODO: RUMM-333 Add boundaries to trace & span ID generation
        return TracingUUID(
            rawValue: .random(in: UInt64.min...UInt64.max)
        )
    }
}

internal typealias TraceID = TracingUUID
internal typealias SpanID = TracingUUID
