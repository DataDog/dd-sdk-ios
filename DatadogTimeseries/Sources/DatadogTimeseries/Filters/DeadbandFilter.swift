/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Suppresses samples whose value has not changed meaningfully since the last emitted sample.
/// Use for slow-changing metrics like memory usage and battery level.
public final class DeadbandFilter: SampleFilter {
    private let threshold: Double
    private let heartbeatInterval: Int64?

    private var lastEmittedValue: Double?
    private var lastEmittedTimestamp: Int64?

    public init(threshold: Double, heartbeatInterval: Int64? = nil) {
        self.threshold = threshold
        self.heartbeatInterval = heartbeatInterval
    }

    public func process(_ sample: Sample) -> [Sample] {
        guard let lastValue = lastEmittedValue, let lastTimestamp = lastEmittedTimestamp else {
            lastEmittedValue = sample.value
            lastEmittedTimestamp = sample.timestamp
            return [sample]
        }

        let valueChanged = abs(sample.value - lastValue) >= threshold
        let heartbeatDue = heartbeatInterval.map { sample.timestamp - lastTimestamp >= $0 } ?? false

        if valueChanged || heartbeatDue {
            lastEmittedValue = sample.value
            lastEmittedTimestamp = sample.timestamp
            return [sample]
        }

        return []
    }

    public func flush() -> [Sample] {
        return []
    }
}
