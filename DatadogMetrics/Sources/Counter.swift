/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public final class Counter {
    let meter: Meter

    /// Create a new `Counter`.
    public init(
        name: String,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        interval: TimeInterval = 1,
        unit: String? = nil,
        tags: [String] = []
    ) {
        self.meter = Meter(
            name: name,
            type: .count,
            interval: Int64(withNoOverflow: interval),
            unit: unit,
            resources: [],
            tags: tags,
            core: core
        )
    }

    /// Increment the counter.
    ///
    /// - parameters:
    ///     - by: Amount to increment by.
    public func increment<FloatingPoint>(by amount: FloatingPoint = 1) where FloatingPoint: BinaryFloatingPoint {
        meter.record(Double(amount))
    }

    /// Increment the counter.
    ///
    /// - parameters:
    ///     - by: Amount to increment by.
    public func increment<Integer>(by amount: Integer) where Integer: BinaryInteger {
        meter.record(Double(amount))
    }
}
