/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogProfiler

internal protocol ScenarioConfiguration {
    /// The name used in UI.
    var name: String { get }
    /// The ID used in metrics.
    var id: String { get }
    /// Creates the view controller that plays this scenario.
    func instantiateInitialViewController() -> UIViewController
}

internal struct Benchmark {
    var duration: TimeInterval = 60
    var runType: RunType = .baseline
    var skipUploads = false
    var scenario: Scenario? = nil
    var instruments: [Instrument] = []

    var env: Env = .local
    var metricTags: [String] {
        ["source:ios", "service:ios-benchmark", "run:\(runType.rawValue)", "env:\(env.rawValue)"]
    }

    enum RunType: String, CaseIterable {
        case baseline = "baseline"
        case instrumented = "instrumented"
    }

    enum Env: String, CaseIterable {
        case local = "local"
        case synthetics = "synthetics"
    }

    enum Scenario: CaseIterable {
        case debug
        case logs
        case rum
        case sr

        var configuration: ScenarioConfiguration {
            switch self {
            case .debug: return DebugScenario()
            case .logs: return LogsScenario()
            case .rum: return RUMScenario()
            case .sr: return SessionReplayScenario()
            }
        }
    }

    enum Instrument {
        case memory(samplingInterval: TimeInterval)
    }

    var instrumentConfigurations: [InstrumentConfiguration] {
        guard let scenarioConfiguration = scenario?.configuration else {
            return []
        }

        return instruments.map { instrument in
            switch instrument {
            case let .memory(samplingInterval):
                return MemoryInstrumentConfiguration(
                    samplingInterval: samplingInterval,
                    metricName: "benchmark.ios.\(scenarioConfiguration.id).memory",
                    metricTags: metricTags
                )
            }
        }
    }
}
