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

    func prepareInstrumentedRun(for benchmark: Benchmark)
    func prepareBaselineRun(for benchmark: Benchmark)

    /// Creates the view controller that plays this scenario.
    func instantiateInitialViewController() -> UIViewController
}

internal struct Benchmark {
    var duration: TimeInterval = Environment.isDebug ? 5 : 5 * 60
    var runType: RunType = .baseline
    var skipUploads = Environment.isDebug ? Environment.skipBenchmarkDataUpload : false
    var scenario: Scenario? = Environment.isDebug ? .debug : nil
    var instruments: [Instrument] = [
        .memory(samplingInterval: 1),
        .batchingAndUpload
    ]

    let service: String = "ios-benchmark"
    var env: Env = Environment.isDebug ? .local : .synthetics
    var metricTags: [String] {
        ["source:ios", "service:\(service)", "run:\(runType.rawValue)", "env:\(env.rawValue)"]
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
        case batchingAndUpload
    }

    var instrumentConfigurations: [InstrumentConfiguration] {
        guard let scenarioConfiguration = scenario?.configuration else {
            return []
        }

        var configurations: [InstrumentConfiguration] = []

        instruments.forEach { instrument in
            switch instrument {
            case let .memory(samplingInterval):
                let memory = MemoryInstrumentConfiguration(
                    samplingInterval: samplingInterval,
                    metricName: "benchmark.ios.\(scenarioConfiguration.id).memory",
                    metricTags: metricTags
                )
                configurations.append(memory)
            case .batchingAndUpload:
                let writes = MetricInstrumentConfiguration(
                    metricName: dataWriteMetricName(for: scenarioConfiguration),
                    metricTags: metricTags
                )
                let uploads = MetricInstrumentConfiguration(
                    metricName: dataUploadMetricName(for: scenarioConfiguration),
                    metricTags: metricTags
                )
                configurations.append(writes)
                configurations.append(uploads)
            }
        }

        return configurations
    }
}

func dataWriteMetricName(for scenarioConfiguration: ScenarioConfiguration) -> String {
    "benchmark.ios.\(scenarioConfiguration.id).data_write"
}

func dataUploadMetricName(for scenarioConfiguration: ScenarioConfiguration) -> String {
    "benchmark.ios.\(scenarioConfiguration.id).data_upload"
}
