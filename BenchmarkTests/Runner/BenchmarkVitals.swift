/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogBenchmarks

/// Collect Vital Metrics such CPU, Memory, and FPS.
///
/// The metrics are reported via DatadogBenchmarks meter provider.
internal final class Vitals {
    let provider: MeterProvider

    private lazy var meter: DatadogBenchmarks.Meter = provider.get(instrumentationName: "vitals")

    let queue = DispatchQueue(label: "com.datadoghq.benchmarks.vitals", target: .global(qos: .utility))

    init(provider: MeterProvider) {
        self.provider = provider
    }

    @discardableResult
    func observeMemory() -> ObservableGauge {
        let memory = Memory(queue: queue)
        return meter.createDoubleObservableGauge(name: "ios.benchmark.memory") { metric in
            // report the maximum memory footprint that was recorded during push interval
            if let value = memory.aggregation?.max {
                metric.observe(value: value, attributes: [:])
            }

            memory.reset()
        }
    }

    @discardableResult
    func observeCPU() -> ObservableGauge {
        let cpu = CPU(queue: queue)
        return meter.createDoubleObservableGauge(name: "ios.benchmark.cpu") { metric in
            // report the average cpu usage that was recorded during push interval
            if let value = cpu.aggregation?.avg {
                metric.observe(value: value, attributes: [:])
            }

            cpu.reset()
        }
    }

    @discardableResult
    func observeFPS() -> ObservableGauge {
        let fps = FPS()
        return meter.createDoubleObservableGauge(name: "ios.benchmark.fps.min") { metric in
            // report the minimum frame rate that was recorded during push interval
            if let value = fps.aggregation?.min {
                metric.observe(value: Double(value), attributes: [:])
            }

            fps.reset()
        }
    }
}
