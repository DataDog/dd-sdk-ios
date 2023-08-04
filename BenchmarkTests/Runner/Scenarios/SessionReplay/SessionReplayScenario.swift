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

    let duration: TimeInterval = Environment.isDebug ? 20 : Synthetics.testDuration
    let fixtureChangeInterval: TimeInterval = Environment.isDebug ? 0.5 : 10

    init(runType: ScenarioRunType) {
        self.runType = runType
    }

    private var rootViewController: SessionReplayScenarioViewController! = nil

    func setUp() {
        debug("SessionReplayScenario.setUp()")

        // Pre-load all view controllers before test is started, to ease memory allocations during the test.
        rootViewController = SessionReplayScenarioViewController(
            fixtureViewControllers: Fixture.allCases.map { $0.instantiateViewController() },
            fixtureChangeInterval: fixtureChangeInterval
        )
        rootViewController.onceAfterAllFixturesLoaded = {
            debug("All fixtures loaded and displayed, start measurements.")
            BenchmarkController.current?.startMeasurements()
        }

        guard runType == .instrumented else {
            return
        }

        // Enable SDK, RUM and SR:
        var sdkConfig = Datadog.Configuration(clientToken: Environment.readClientToken(), env: Environment.readEnv())
        sdkConfig.service = Environment.service
        Datadog.initialize(with: sdkConfig, trackingConsent: .granted)

        var rumConfig = RUM.Configuration(applicationID: Environment.readRUMApplicationID())
        rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()

        RUM.enable(with: rumConfig)

        let srConfig = SessionReplay.Configuration(replaySampleRate: 100)
        SessionReplay.enable(with: srConfig)

        if Environment.isDebug {
            Datadog.verbosityLevel = .debug
            RUMMonitor.shared().debug = true
        }
    }

    func tearDown() {
        debug("SessionReplayScenario.tearDown()")
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

    /// Measurements will be started after each fixture is displayed at least once.
    /// This is to further ease memory allocations during the test.
    let startMeasurementsAutomatically = false

    func instantiateInitialViewController() -> UIViewController {
        rootViewController
    }
}
