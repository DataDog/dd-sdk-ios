/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class MetricTelemetryAggregator {
    private struct AggregationKey: Hashable {
        let metric: String
        let cardinalities: MetricTelemetry.Cardinalities
    }

    let sampleRate: SampleRate

    @ReadWriteLock
    private var aggregations: [AggregationKey: Double] = [:]

    init(sampleRate: SampleRate = .maxSampleRate) {
        self.sampleRate = sampleRate
    }

    func increment(_ metric: String, by value: Double, cardinalities: MetricTelemetry.Cardinalities) {
        _aggregations.mutate { $0[AggregationKey(metric: metric, cardinalities: cardinalities), default: 0] += value }
    }

    func record(_ metric: String, value: Double, cardinalities: MetricTelemetry.Cardinalities) {
        _aggregations.mutate { $0[AggregationKey(metric: metric, cardinalities: cardinalities), default: 0] = value }
    }

    func flush() -> [MetricTelemetry.Event] {
        _aggregations.mutate { counters in
            defer { counters = [:] }

            return counters.map { key, value in
                var attributes: [String: Encodable] = key.cardinalities
                attributes[SDKMetricFields.typeKey] = key.metric
                attributes[SDKMetricFields.valueKey] = value
                return MetricTelemetry.Event(
                    name: key.metric,
                    attributes: attributes,
                    sampleRate: sampleRate
                )
            }
        }
    }
}
