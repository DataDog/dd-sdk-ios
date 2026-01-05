/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogBenchmarks
import OpenTelemetryApi
import OpenTelemetrySdk

/// Collect Vital Metrics such CPU, Memory, and FPS.
///
/// The metrics are reported via opentelemetry.
internal final class Vitals {
    let provider: MeterProviderSdk

    private lazy var meter: MeterSdk = provider.get(name: "vitals")

    let queue = DispatchQueue(label: "com.datadoghq.benchmarks.vitals", target: .global(qos: .utility))

    init(provider: MeterProviderSdk) {
        self.provider = provider
    }

    @discardableResult
    func observeMemory() -> ObservableInstrumentSdk {
        let memory = Memory(queue: queue)
        return meter.gaugeBuilder(name: "ios.benchmark.memory").buildWithCallback { measurement in
            // report the maximum memory footprint that was recorded during push interval
            if let value = memory.aggregation?.max {
                measurement.record(value: value)
            }

            memory.reset()
        }
    }

    @discardableResult
    func observeCPU() -> ObservableInstrumentSdk {
        let cpu = CPU(queue: queue)
        return meter.gaugeBuilder(name: "ios.benchmark.cpu").buildWithCallback { measurement in
            // report the average cpu usage that was recorded during push interval
            if let value = cpu.aggregation?.avg {
                measurement.record(value: value)
            }

            cpu.reset()
        }
    }

    @discardableResult
    func observeFPS() -> ObservableInstrumentSdk {
        let fps = FPS()
        return meter.gaugeBuilder(name: "ios.benchmark.fps.min").ofLongs().buildWithCallback { measurement in
            // report the minimum frame rate that was recorded during push interval
            if let value = fps.aggregation?.min {
                measurement.record(value: value)
            }

            fps.reset()
        }
    }
}
