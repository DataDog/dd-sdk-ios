/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogBenchmarks

internal final class Meter: DatadogInternal.BenchmarkMeter {
    let meter: DatadogBenchmarks.Meter

    init(provider: MeterProvider) {
        self.meter = provider.get(instrumentationName: "benchmarks")
    }

    func counter(metric: @autoclosure () -> String) -> DatadogInternal.BenchmarkCounter {
        DoubleCounter(counter: meter.createDoubleCounter(name: metric()))
    }

    func gauge(metric: @autoclosure () -> String) -> DatadogInternal.BenchmarkGauge {
        DoubleMeasure(measure: meter.createDoubleMeasure(name: metric()))
    }

    func observe(metric: @autoclosure () -> String, callback: @escaping (any DatadogInternal.BenchmarkGauge) -> Void) {
        _ = meter.createDoubleObservableGauge(name: metric()) { observer in
            callback(DoubleObserver(observer: observer))
        }
    }
}

private struct DoubleCounter: DatadogInternal.BenchmarkCounter {
    let counter: DatadogBenchmarks.DoubleCounter

    func add(value: Double, attributes: @autoclosure () -> [String: String]) {
        counter.add(value: value, attributes: attributes())
    }
}

private struct DoubleMeasure: DatadogInternal.BenchmarkGauge {
    let measure: DatadogBenchmarks.DoubleMeasure

    func record(value: Double, attributes: @autoclosure () -> [String: String]) {
        measure.record(value: value, attributes: attributes())
    }
}

private struct DoubleObserver: DatadogInternal.BenchmarkGauge {
    let observer: DatadogBenchmarks.DoubleObserver

    func record(value: Double, attributes: @autoclosure () -> [String: String]) {
        observer.observe(value: value, attributes: attributes())
    }
}
