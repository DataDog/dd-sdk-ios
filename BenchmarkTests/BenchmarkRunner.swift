/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogProfiler

internal class BenchmarkRunner {
    private unowned var app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
    }

    func run(benchmark: Benchmark) {
        guard !benchmark.instruments.isEmpty, let scenario = benchmark.scenario else {
            debug("No instruments configured, skipping benchmark.")
            return
        }

        Profiler.setUp(
            with: ProfilerConfiguration(apiKey: Environment.apiKey()),
            instruments: benchmark.instrumentConfigurations,
            expectedMeasurementDuration: benchmark.duration
        )
        Profiler.skipUploads = Environment.skipUploadingBenchmarkResult

        let scenarioVC = scenario.configuration.instantiateInitialViewController()
        app.setRoot(viewController: scenarioVC) {
            Profiler.instance!.start(
                stopAndTearDownAutomatically: { [unowned self] result in
                    self.onBenchmarkCompleted(benchmark: benchmark, result: result)
                }
            )
        }
    }

    private func onBenchmarkCompleted(benchmark: Benchmark, result: ProfilerUploadResult) {
        let endVC = UIStoryboard.main.instantiateViewController(withIdentifier: BenchmarkEndViewController.storyboardID) as! BenchmarkEndViewController
        endVC.loadViewIfNeeded()
        endVC.statusLabel.text = result.isSuccess ? "Data upload succeeded." : "Data upload failed."
        endVC.detailsLabel.text = "Scenario: \(benchmark.scenario!.configuration.name)" + "\n" + result.summary.joined(separator: "\n")
        app.setRoot(viewController: endVC)
    }
}
