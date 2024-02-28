/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import DatadogInternal

internal class DatadogMeasureMetric<Value>: BoundMeasureMetric<Value>, MeasureMetric where Value: OpenTelemetryMetricValue {
    let meter: Meter

    required init(meter: Meter) {
        self.meter = meter
    }

    func bind(labelset: OpenTelemetryApi.LabelSet) -> BoundMeasureMetric<Value> {
        bind(labels: labelset.labels)
    }

    func bind(labels: [String: String]) -> BoundMeasureMetric<Value> {
        Self(meter: Meter(meter, labels: labels))
    }

    override func record(value: Value) {
        meter.record(value.doubleValue)
    }
}
