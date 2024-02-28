/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public final class Gauge {
    let meter: Meter

    /// Create a new `Gauge`.
    public required init(
        name: String,
        in core: DatadogCoreProtocol = CoreRegistry.default,
        interval: TimeInterval = 1,
        unit: String? = nil,
        tags: [String] = []
    ) {
        self.meter = Meter(
            name: name,
            type: .gauge,
            interval: Int64(withNoOverflow: interval),
            unit: unit,
            resources: [],
            tags: tags,
            core: core
        )
    }

    /// Record value.
    public func record<FloatingPoint>(_ value: FloatingPoint) where FloatingPoint: BinaryFloatingPoint {
        meter.record(Double(value))
    }

    /// Record value.
    public func record<Integer>(_ value: Integer) where Integer: BinaryInteger {
        meter.record(Double(value))
    }
}
