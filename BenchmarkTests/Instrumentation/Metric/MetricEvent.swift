/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// POST https://api.datadoghq.com/api/v2/series
/// Ref.: https://docs.datadoghq.com/api/latest/metrics/#submit-metrics
///
/// Limits?
/// - 64 bits for the timestamp
/// - 64 bits for the value
/// - 20 bytes for the metric names
/// - 50 bytes for the timeseries
/// - The full payload is approximately 100 bytes.
internal struct MetricEvent: Encodable {
    struct Series: Encodable {
        struct Point: Encodable {
            /// The timestamp should be in seconds and current. Current is defined as not more than 10 minutes in the future or more than 1 hour in the past.
            let timestamp: UInt64
            /// The numeric value format should be a 64bit float gauge-type value
            let value: Double
        }

        struct Metadata: Encodable {
            struct Origin: Encodable {
                /// The origin metric type code
                let metricType: Int32
                /// The origin product code
                let product: Int32
                /// The origin service code
                let service: Int32
            }

            /// Metric origin information.
            let origin: Origin
        }

        struct Resource: Encodable {
            /// The name of the resource.
            let name: String
            /// The type of the resource.
            let type: String
        }

        enum MetricType: Int, Encodable {
            case unspecified = 0
            case count = 1
            case rate = 2
            case gauge = 3
        }

        /// If the type of the metric is rate or count, define the corresponding interval.
        var interval: UInt64? = nil

        /// Metadata for the metric.
        var metadata: Metadata? = nil

        /// The name of the timeseries.
        var metric: String

        /// Points relating to a metric.
        /// All points must be objects with timestamp and a scalar value (cannot be a string).
        /// Timestamps should be in POSIX time in seconds, and cannot be more than ten minutes in the future or more than one hour in the past.
        var points: [Point]

        /// A list of resources to associate with this metric.
        var resources: [Resource]? = nil

        /// The source type name.
        var sourceTypeName: String? = nil

        /// A list of tags associated with the metric.
        var tags: [String]? = nil

        /// The type of metric.
        var type: MetricType

        /// The unit of point value.
        var unit: String? = nil
    }

    /// A list of time series to submit to Datadog.
    var series: [Series]
}
