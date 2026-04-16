/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum AggregateFunction {
    case avg, min, max, last
}

/// Aggregates samples into fixed time windows and emits one value per window.
/// Use for noisy continuous metrics like CPU usage and frame rate.
public final class WindowAggregateFilter: SampleFilter {
    private let windowDuration: Int64
    private let function: AggregateFunction

    private var windowStart: Int64?
    private var buffer: [Sample] = []

    public init(windowDuration: Int64, function: AggregateFunction = .max) {
        self.windowDuration = windowDuration
        self.function = function
    }

    public func process(_ sample: Sample) -> [Sample] {
        guard let start = windowStart else {
            windowStart = sample.timestamp
            buffer.append(sample)
            return []
        }

        if sample.timestamp - start >= windowDuration {
            let aggregateSample = Sample(timestamp: start, value: aggregate(buffer))
            windowStart = sample.timestamp
            buffer = [sample]
            return [aggregateSample]
        }

        buffer.append(sample)
        return []
    }

    public func flush() -> [Sample] {
        guard !buffer.isEmpty else {
            return []
        }

        let aggregateSample = Sample(timestamp: windowStart!, value: aggregate(buffer))
        buffer = []
        return [aggregateSample]
    }

    private func aggregate(_ samples: [Sample]) -> Double {
        switch function {
        case .avg:
            return samples.reduce(0.0) { $0 + $1.value } / Double(samples.count)
        case .min:
            return samples.min(by: { $0.value < $1.value })!.value
        case .max:
            return samples.max(by: { $0.value < $1.value })!.value
        case .last:
            return samples.last!.value
        }
    }
}
