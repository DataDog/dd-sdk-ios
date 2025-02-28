/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// The Synthetics Scenario reads the `BENCHMARK_SCENARIO` environment
/// variable to instantiate a `Scenario` compliant object.
internal struct SyntheticScenario: Scenario {
    /// The Synthetics benchmark scenario value.
    internal enum Name: String {
        case sessionReplay
        case sessionReplaySwiftUI
        case logsCustom
    }
    /// The scenario's name.
    let name: Name

    /// The underlying scenario.
    private let _scenario: Scenario

    /// Creates the scenario by reading the `BENCHMARK_SCENARIO` value from the
    /// environment variables.
    ///
    /// - Parameter processInfo: The `ProcessInfo` with environment variables
    /// configured
    init?(processInfo: ProcessInfo = .processInfo) {
        guard
            let rawValue = processInfo.environment["BENCHMARK_SCENARIO"],
            let name = Name(rawValue: rawValue)
        else {
            return nil
        }

        switch name {
        case .sessionReplay:
            _scenario = SessionReplayScenario()
        case .sessionReplaySwiftUI:
            _scenario = SessionReplaySwiftUIScenario()
        case .logsCustom:
            _scenario = LogsCustomScenario()
        }

        self.name = name
    }

    var initialViewController: UIViewController {
        _scenario.initialViewController
    }

    func instrument(with info: AppInfo) {
        _scenario.instrument(with: info)
    }
}

/// The Synthetics benchmark run.
///
/// The run specifies the execution context of a benchmark scenrio.
/// Each execution will collect different type of benchmarking data:
///     - The `baseline` run collects various metrics during the scenario execution **without**
///     the Datadog SDK being initialised.
///     -  The `instrumented` run collects the same metrics as `baseline` but **with** the
///     Datadog SDK initialised. Comparing the `baseline` and `instrumented` runs will provide
///     the overhead of the SDK for each metric.
///     - The `profiling` run will only collect traces of the SDK internal processes.
internal enum SyntheticRun: String {
    case baseline
    case instrumented
    case profiling
    case none

    /// Creates the scenario by reading the `BENCHMARK_RUN` value from the
    /// environment variables.
    ///
    /// - Parameter processInfo: The `ProcessInfo` with environment variables
    /// configured
    init(processInfo: ProcessInfo = .processInfo) {
        self = processInfo
            .environment["BENCHMARK_RUN"]
            .flatMap(Self.init(rawValue:))
        ?? .none
    }
}
