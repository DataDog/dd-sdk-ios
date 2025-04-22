/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A class that aggregates metric telemetry data before sending it to the Datadog.
///
/// This aggregator supports two types of metrics:
/// - Counter metrics: Values that can only increase (e.g., number of events)
/// - Gauge metrics: Values that can go up and down (e.g., current memory usage)
///
/// Metrics can be aggregated along different dimensions using cardinalities, allowing for
/// detailed analysis of metric data across various contexts.
internal final class MetricTelemetryAggregator {
    private typealias AggregationKey = MetricTelemetry.Cardinalities
    private typealias AggregationValue = [String: Double]

    /// The sample rate to apply to aggregated metrics.
    let sampleRate: SampleRate

    /// Thread-safe storage for metric aggregations.
    @ReadWriteLock
    private var aggregations: [AggregationKey: AggregationValue] = [:]

    /// Creates a new metric telemetry aggregator.
    ///
    /// - Parameter sampleRate: The sample rate to apply to aggregated metrics.
    ///   Defaults to maximum sample rate (100%).
    init(sampleRate: SampleRate = .maxSampleRate) {
        self.sampleRate = sampleRate
    }

    /// Increments a counter metric by a specified value.
    ///
    /// This method adds the specified value to the current value of the metric.
    /// If the metric doesn't exist, it will be initialized with the specified value.
    ///
    /// - Parameters:
    ///   - metric: The name of the metric to increment.
    ///   - value: The amount to increment the metric by.
    ///   - cardinalities: The dimensions along which the metric will be aggregated.
    func increment(_ metric: String, by value: Double, cardinalities: MetricTelemetry.Cardinalities) {
        _aggregations.mutate { aggregations in
            var aggregation = aggregations[cardinalities, default: [metric: 0]]
            aggregation[metric, default: 0] += value
            aggregations[cardinalities] = aggregation
        }
    }

    /// Records a gauge metric with a specified value.
    ///
    /// This method sets the metric to the specified value, replacing any previous value.
    /// Gauge metrics are used for values that can fluctuate up and down.
    ///
    /// - Parameters:
    ///   - metric: The name of the metric to record.
    ///   - value: The value to record for the metric.
    ///   - cardinalities: The dimensions along which the metric will be aggregated.
    func record(_ metric: String, value: Double, cardinalities: MetricTelemetry.Cardinalities) {
        _aggregations.mutate { aggregations in
            var aggregation = aggregations[cardinalities, default: [metric: 0]]
            aggregation[metric, default: 0] = value
            aggregations[cardinalities] = aggregation
        }
    }

    /// Flushes all aggregated metrics and returns them as telemetry events.
    ///
    /// This method:
    /// 1. Converts all aggregated metrics into telemetry events
    /// 2. Clears the internal aggregation storage
    /// 3. Returns the generated events
    ///
    /// - Returns: An array of metric telemetry events ready to be sent to the backend.
    func flush() -> [MetricTelemetry.Event] {
        _aggregations.mutate { aggregations in
            defer { aggregations = [:] }

            return aggregations.map { key, value in
                // Group metrics with same cardinality in the same
                // telemetry event
                var attributes: [String: Encodable] = key
                attributes.merge(value, uniquingKeysWith: { $1 })
                return MetricTelemetry.Event(
                    name: value.keys.joined(separator: ","),
                    attributes: attributes,
                    sampleRate: sampleRate
                )
            }
        }
    }
}
