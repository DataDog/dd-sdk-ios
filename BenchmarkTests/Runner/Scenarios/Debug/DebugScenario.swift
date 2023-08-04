/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// Debug scenario, used mainly to debug and callibrate instrumentations.
internal class DebugScenario: BenchmarkScenario {
    let title = "Debug"
    let scenarioTagValue = "debug"
    let duration: TimeInterval = 10

    func beforeRun() {
        debug("DebugScenario.beforeRun()")
    }

    func afterRun() {
        debug("DebugScenario.afterRun()")
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

    func instantiateInitialViewController() -> UIViewController { UIStoryboard.debug.instantiateInitialViewController()! }
}
