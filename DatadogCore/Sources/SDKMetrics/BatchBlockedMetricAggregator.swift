/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class BatchBlockedMetricAggregator {
    private struct AggregationKey: Hashable {
        let track: String
        let failure: String?
        let blockers: [String]?
    }

    let sampleRate: SampleRate

    @ReadWriteLock
    private var aggregations: [AggregationKey: Int] = [:]

    init(sampleRate: SampleRate = MetricTelemetry.defaultSampleRate) {
        self.sampleRate = sampleRate
    }

    func increment(by count: Int, track: String, failure: String) {
        increment(by: count, key: AggregationKey(track: track, failure: failure, blockers: nil))
    }

    func increment(by count: Int, track: String, blockers: [String]) {
        increment(by: count, key: AggregationKey(track: track, failure: nil, blockers: blockers))
    }

    private func increment(by count: Int, key: AggregationKey) {
        _aggregations.mutate { $0[key, default: 0] += count }
    }

    func flush() -> [MetricTelemetry] {
        _aggregations.mutate { aggregations in
            defer { aggregations = [:] }

            return aggregations.compactMap { key, value in
                if let failure = key.failure {
                    return MetricTelemetry(
                        name: BatchBlockedMetric.name,
                        attributes: [
                            SDKMetricFields.typeKey: BatchBlockedMetric.typeValue,
                            BatchMetric.trackKey: key.track,
                            BatchBlockedMetric.batchCount: value,
                            BatchBlockedMetric.failure: failure
                        ],
                        sampleRate: sampleRate
                    )
                }

                if let blockers = key.blockers {
                    return MetricTelemetry(
                        name: BatchBlockedMetric.name,
                        attributes: [
                            SDKMetricFields.typeKey: BatchBlockedMetric.typeValue,
                            BatchMetric.trackKey: key.track,
                            BatchBlockedMetric.batchCount: value,
                            BatchBlockedMetric.blockers: blockers
                        ],
                        sampleRate: sampleRate
                    )
                }

                return nil
            }
        }
    }
}
