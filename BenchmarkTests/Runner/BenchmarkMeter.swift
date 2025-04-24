/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogBenchmarks
import OpenTelemetryApi

internal final class Meter: DatadogInternal.BenchmarkMeter {
    let meter: OpenTelemetryApi.Meter

    init(provider: MeterProvider) {
        self.meter = provider.get(
            instrumentationName: "benchmarks",
            instrumentationVersion: nil
        )
    }

    func counter(metric: @autoclosure () -> String) -> DatadogInternal.BenchmarkCounter {
        meter.createDoubleCounter(name: metric())
    }

    func gauge(metric: @autoclosure () -> String) -> DatadogInternal.BenchmarkGauge {
        meter.createDoubleMeasure(name: metric())
    }

    func observe(metric: @autoclosure () -> String, callback: @escaping (any DatadogInternal.BenchmarkGauge) -> Void) {
        _ = meter.createDoubleObserver(name: metric()) { callback(DoubleObserverWrapper(observer: $0)) }
    }
}

extension AnyCounterMetric<Double>: DatadogInternal.BenchmarkCounter {
    public func add(value: Double, attributes: @autoclosure () -> [String: String]) {
        add(value: value, labelset: LabelSet(labels: attributes()))
    }
}

extension AnyMeasureMetric<Double>: DatadogInternal.BenchmarkGauge {
    public func record(value: Double, attributes: @autoclosure () -> [String: String]) {
        record(value: value, labelset: LabelSet(labels: attributes()))
    }
}

private struct DoubleObserverWrapper: DatadogInternal.BenchmarkGauge {
    let observer: DoubleObserverMetric

    func record(value: Double, attributes: @autoclosure () -> [String: String]) {
        observer.observe(value: value, labelset: LabelSet(labels: attributes()))
    }
}
