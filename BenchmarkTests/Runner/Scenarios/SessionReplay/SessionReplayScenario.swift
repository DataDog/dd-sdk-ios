/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogRUM
import DatadogSessionReplay

/// Session Replay scenario - switches between SR snapshots with changing the RUM view each time.
internal class SessionReplayScenario: BenchmarkScenario {
    let runType: ScenarioRunType

    var title: String { "Session Replay (\(runType))" }

    let duration: TimeInterval = Environment.isDebug ? 10 : 5 * 60
    let fixtureChangeInterval: TimeInterval = Environment.isDebug ? 1 : 10

    init(runType: ScenarioRunType) {
        self.runType = runType
    }

    private var rootViewController: UIViewController! = nil

    func beforeRun() {
        debug("SessionReplayScenario.beforeRun()")

        // Pre-load all view controllers before test is started, to ease memory allocations during the test.
        rootViewController = SessionReplayScenarioViewController(
            fixtureViewControllers: Fixture.allCases.map { fixture in
                let vc = fixture.instantiateViewController()
                vc.loadView()
                return vc
            },
            fixtureChangeInterval: fixtureChangeInterval
        )

        guard runType == .instrumented else {
            return
        }

        // Enable SDK, RUM and SR:
        let sdkConfig = Datadog.Configuration(clientToken: Environment.readClientToken(), env: Environment.readEnv())
        Datadog.initialize(with: sdkConfig, trackingConsent: .granted)

        var rumConfig = RUM.Configuration(applicationID: Environment.readRUMApplicationID())
        rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()

        RUM.enable(with: rumConfig)

        let srConfig = SessionReplay.Configuration(replaySampleRate: 100)
        SessionReplay.enable(with: srConfig)
    }

    func afterRun() {
        debug("SessionReplayScenario.afterRun()")
        guard runType == .instrumented else {
            return
        }
        Datadog.clearAllData()
    }

    func instruments() -> [Instrument] {
        let memoryMetric = MetricConfiguration(
            name: "benchmark.ios.sr.memory",
            tags: Environment.readCommonMetricTags() + ["run:\(runType)"],
            type: .gauge
        )
        let memory = MemoryUsageInstrument(
            samplingInterval: Environment.isDebug ? 0.5 : 2,
            metricUploader: MetricUploader(metricConfiguration: memoryMetric)
        )
        return [memory]
    }

    func instantiateInitialViewController() -> UIViewController {
        rootViewController
    }
}
