/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// Debug scenario, used mainly to debug and callibrate instrumentations.
internal class DebugScenario: BenchmarkScenario {
    let title = "Debug"
    let duration: TimeInterval = 10

    func setUp() {
        debug("DebugScenario.setUp()")
    }

    func tearDown() {
        debug("DebugScenario.tearDown()")
    }

    func instruments() -> [Instrument] {
        let memoryMetric = MetricConfiguration(
            name: "benchmark.ios.debug.memory",
            tags: Environment.readCommonMetricTags() + ["run:\(ScenarioRunType.baseline)"],
            type: .gauge
        )
        let memory = MemoryUsageInstrument(
            samplingInterval: 0.5,
            metricUploader: MetricUploader(metricConfiguration: memoryMetric)
        )
        return [memory]
    }

    let startMeasurementsAutomatically = true

    func instantiateInitialViewController() -> UIViewController { UIStoryboard.debug.instantiateInitialViewController()! }
}
