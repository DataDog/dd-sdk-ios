/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Interface for Telemetry metrics.
internal protocol MetricAttributesConvertible {
    /// Indicates the metric being tracked.
    var metricName: String { get }
    /// Transforms the telemetry data in an encodable dictionary.
    func asMetricAttributes() -> [String: Encodable]?
}

internal final class ProfilingTelemetryController {
    /// Telemetry endpoint for sending metrics.
    let telemetry: Telemetry
    /// Metric with Profiling configurations.
    let configMetric: ConfigurationMetric

    init(telemetry: Telemetry, configMetric: ConfigurationMetric = ConfigurationMetric()) {
        self.telemetry = telemetry
        self.configMetric = configMetric
    }

    /// Sends the telemetry metric.
    func send(metric: MetricAttributesConvertible) {
        guard var metricAttributes = metric.asMetricAttributes() else {
            telemetry.debug("Failed to compute attributes for '\(metric.metricName)'")
            return
        }
        metricAttributes.merge(configMetric.asMetricAttributes() ?? [:]) { $1 }

        telemetry.metric(name: metric.metricName, attributes: metricAttributes, sampleRate: 100.0)
    }
}
