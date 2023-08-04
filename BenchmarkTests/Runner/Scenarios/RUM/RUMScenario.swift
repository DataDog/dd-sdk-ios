/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogRUM

internal class RUMScenario: BenchmarkScenario {
    let runType: ScenarioRunType

    var title: String { "RUM (\(runType))" }

    let duration: TimeInterval = Environment.isDebug ? 30 : Synthetics.testDuration

    init(runType: ScenarioRunType) {
        self.runType = runType
    }

    func setUp() {
        debug("RUMScenario.setUp()")
        guard runType == .instrumented else {
            return
        }

        // Enable SDK and Logs:
        var sdkConfig = Datadog.Configuration(clientToken: Environment.readClientToken(), env: Environment.readEnv())
        sdkConfig.service = Environment.service
        Datadog.initialize(with: sdkConfig, trackingConsent: .granted)

        let rumConfig = RUM.Configuration(applicationID: Environment.readRUMApplicationID())
        RUM.enable(with: rumConfig)

        if Environment.isDebug {
            Datadog.verbosityLevel = .debug
            RUMMonitor.shared().debug = true
        }
    }

    func tearDown() {
        debug("RUMScenario.tearDown()")
        guard runType == .instrumented else {
            return
        }
        Datadog.clearAllData()
    }

    func instruments() -> [Instrument] {
        let memoryMetric = MetricConfiguration(
            name: "benchmark.ios.rum.memory",
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

    func instantiateInitialViewController() -> UIViewController { RUMScenarioViewController(labelText: "Sending RUM events...") }
}
