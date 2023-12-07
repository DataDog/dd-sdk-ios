/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogLogs
import DatadogRUM
import DatadogSessionReplay

import DatadogProfiler

extension UIStoryboard {
    static var main: UIStoryboard { UIStoryboard(name: "Main", bundle: nil) }
    static var debug: UIStoryboard { UIStoryboard(name: "Debug", bundle: nil) }
}

extension ScenarioConfiguration {
    func enableDatadogCore(for benchmark: Benchmark) {
        debug("ScenarioConfiguration.enableDatadogCore()")
        var config = Datadog.Configuration(clientToken: Environment.readClientToken(), env: benchmark.env.rawValue)
        config.service = benchmark.service
        let core = Datadog.initialize(with: config, trackingConsent: .granted)

        if Environment.isDebug {
            Datadog.verbosityLevel = .debug
        }

        core.profilingHooks.onDataUpload = { size in
            let size = Double(size)
            Profiler.instance?.collect(dataPoint: size, metricName: dataUploadMetricName(for: benchmark.scenario!.configuration))
        }

        core.profilingHooks.onDataWrite = { size in
            let size = Double(size)
            Profiler.instance?.collect(dataPoint: size, metricName: dataWriteMetricName(for: benchmark.scenario!.configuration))
        }
    }

    func enableLogs(for benchmark: Benchmark) {
        debug("ScenarioConfiguration.enableLogs()")
        Logs.enable()
    }

    func enableRUM(for benchmark: Benchmark) {
        debug("ScenarioConfiguration.enableRUM()")
        var config = RUM.Configuration(applicationID: Environment.readRUMApplicationID())
        config.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        RUM.enable(with: config)

        if Environment.isDebug {
            RUMMonitor.shared().debug = true
        }
    }

    func enableSR(for benchmark: Benchmark) {
        debug("ScenarioConfiguration.enableSR()")
        var config = SessionReplay.Configuration(replaySampleRate: 100)
        config.defaultPrivacyLevel = .mask
        SessionReplay.enable(with: config)

    }
}
