/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import DatadogInternal

internal class DatadogCounterMetric<Value>: BoundCounterMetric<Value>, CounterMetric where Value: OpenTelemetryMetricValue {
    let meter: Meter

    @Mutex
    var value: Value

    required init(
        meter: Meter,
        value: Value = .zero
    ) {
        self.meter = meter
        self.value = value
    }

    func add(value: Value, labelset: OpenTelemetryApi.LabelSet) {
        add(value: value, labels: labelset.labels)
    }

    func add(value: Value, labels: [String : String]) {
        let meter = Meter(meter, labels: labels)
        _value.lock {
            $0 += value
            meter.record($0.doubleValue)
        }
    }

    func bind(labelset: OpenTelemetryApi.LabelSet) -> BoundCounterMetric<Value> {
        bind(labels: labelset.labels)
    }

    func bind(labels: [String: String]) -> BoundCounterMetric<Value> {
        Self(
            meter: Meter(meter, labels: labels),
            value: value
        )
    }

    override func add(value: Value) {
        _value.lock {
            $0 += value
            meter.record($0.doubleValue)
        }
    }
}
