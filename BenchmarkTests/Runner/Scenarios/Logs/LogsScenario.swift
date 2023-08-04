/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogLogs

internal class LogsScenario: BenchmarkScenario {
    let runType: ScenarioRunType

    var title: String { "Logs (\(runType))" }

    let duration: TimeInterval = Environment.isDebug ? 50 : Synthetics.testDuration

    init(runType: ScenarioRunType) {
        self.runType = runType
    }

    func setUp() {
        debug("LogsScenario.setUp()")
        guard runType == .instrumented else {
            return
        }

        // Enable SDK and Logs:
        var sdkConfig = Datadog.Configuration(clientToken: Environment.readClientToken(), env: Environment.readEnv())
        sdkConfig.service = Environment.service
        Datadog.initialize(with: sdkConfig, trackingConsent: .granted)

        Logs.enable()

        if Environment.isDebug {
            Datadog.verbosityLevel = .debug
        }
    }

    func tearDown() {
        debug("LogsScenario.tearDown()")
        guard runType == .instrumented else {
            return
        }
        Datadog.clearAllData()
    }

    func instruments() -> [Instrument] {
        let memoryMetric = MetricConfiguration(
            name: "benchmark.ios.logs.memory",
            tags: Environment.readCommonMetricTags() + ["run:\(runType)"],
            type: .gauge
        )
        let memory = MemoryUsageInstrument(
            samplingInterval: Environment.isDebug ? 0.5 : 2,
            metricUploader: MetricUploader(metricConfiguration: memoryMetric)
        )
        return [memory]
    }

    let startMeasurementsAutomatically = true

    func instantiateInitialViewController() -> UIViewController { LogsScenarioViewController(labelText: "Sending logs...") }
}
