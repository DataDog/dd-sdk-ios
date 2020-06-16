/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol TracingUUIDGenerator {
    func generateUnique() -> TracingUUID
}

internal struct DefaultTracingUUIDGenerator: TracingUUIDGenerator {
    /// Describes the lower and upper boundary of tracing ID generation.
    /// * Lower: starts with `1` as `0` is reserved for historical reason: 0 == "unset", ref: dd-trace-java:DDId.java.
    /// * Upper: equals to `2 ^ 63 - 1` as some tracers can't handle the `2 ^ 64 -1` range, ref: dd-trace-java:DDId.java.
    internal static let defaultGenerationRange = (1...UInt64.max >> 1)

    internal let range: ClosedRange<UInt64>

    init(range: ClosedRange<UInt64> = Self.defaultGenerationRange) {
        self.range = range
    }

    func generateUnique() -> TracingUUID {
        return TracingUUID(rawValue: .random(in: range))
   }
}
