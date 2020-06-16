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
    /// Lower boundary of `TracingUUID`.
    /// `0` is reserved for historical reason: 0 == "unset", ref: dd-trace-java:DDId.java.
    internal static let min: UInt64 = 1
    /// Upper boundary of `TracingUUID`.
    /// It equals to `2 ^ 63 - 1` because some tracers can't handle the `2 ^ 64 -1` range, ref: dd-trace-java:DDId.java.
    internal static let max = UInt64.max >> 1

    internal let min: UInt64
    internal let max: UInt64

    init(
        lowerBoundary: UInt64 = DefaultTracingUUIDGenerator.min,
        upperBoundary: UInt64 = DefaultTracingUUIDGenerator.max
    ) {
        self.min = lowerBoundary
        self.max = upperBoundary
    }

    func generateUnique() -> TracingUUID {
        return TracingUUID(rawValue: .random(in: min...max))
   }
}
