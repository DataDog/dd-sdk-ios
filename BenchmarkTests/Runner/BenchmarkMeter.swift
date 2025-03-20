/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogBenchmarks
import OpenTelemetryApi
import OpenTelemetrySdk

internal final class Meter: DatadogInternal.BenchmarkMeter {
    let meter: OpenTelemetryApi.Meter

    let queue = DispatchQueue(label: "com.datadoghq.benchmarks.metrics", target: .global(qos: .utility))

    init(provider: MeterProvider) {
        self.meter = provider.get(
            instrumentationName: "benchmarks",
            instrumentationVersion: nil
        )
    }

    @discardableResult
    func observeMemory() -> OpenTelemetryApi.DoubleObserverMetric {
        let memory = Memory(queue: queue)
        return meter.createDoubleObservableGauge(name: "ios.benchmark.memory") { metric in
            // report the maximum memory footprint that was recorded during push interval
            if let value = memory.aggregation?.max {
                metric.observe(value: value, labelset: .empty)
            }

            memory.reset()
        }
    }

    @discardableResult
    func observeCPU() -> OpenTelemetryApi.DoubleObserverMetric {
        let cpu = CPU(queue: queue)
        return meter.createDoubleObservableGauge(name: "ios.benchmark.cpu") { metric in
            // report the average cpu usage that was recorded during push interval
            if let value = cpu.aggregation?.avg {
                metric.observe(value: value, labelset: .empty)
            }

            cpu.reset()
        }
    }

    @discardableResult
    func observeFPS() -> OpenTelemetryApi.IntObserverMetric {
        let fps = FPS()
        return meter.createIntObservableGauge(name: "ios.benchmark.fps.min") { metric in
            // report the minimum frame rate that was recorded during push interval
            if let value = fps.aggregation?.min {
                metric.observe(value: value, labelset: .empty)
            }

            fps.reset()
        }
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
