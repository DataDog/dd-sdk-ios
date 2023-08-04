/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// Coordinates execution of a single benchmark.
internal class BenchmarkController {
    private(set) static var current: BenchmarkController?

    // MARK: - Instance

    private let instruments: [Instrument]
    internal let scenario: BenchmarkScenario

    private(set) var isRunning = false

    private init(scenario: BenchmarkScenario) {
        self.instruments = scenario.instruments()
        self.scenario = scenario
    }

    // MARK: - Control

    static func set(scenario: BenchmarkScenario) {
        precondition((current?.isRunning ?? false) == false, "Previous benchmark must end before starting a new one")
        current = BenchmarkController(scenario: scenario)
    }

    static func run() {
        precondition((current?.isRunning ?? false) == false, "Previous benchmark must end before starting a new one")
        current?.run()
    }

    private func run() {
        let app = UIApplication.shared.delegate as! AppDelegate
        beforeStart()
        scenario.beforeRun()

        let scenarioVC = scenario.instantiateInitialViewController()
        app.show(viewController: scenarioVC) { [weak self] in
            self?.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + scenario.duration) { [weak self] in
            self?.stop()
            self?.scenario.afterRun()

            let endVC = UIStoryboard.main.instantiateViewController(withIdentifier: BenchmarkEndViewController.storyboardID) as! BenchmarkEndViewController
            endVC.loadViewIfNeeded()
            endVC.statusLabel.text = "Uploading data..."
            endVC.closeButton.isHidden = true
            endVC.onClose = {
                app.goBackToMenu {
                    BenchmarkController.current = nil
                }
            }
            app.show(viewController: endVC) { [weak self] in
                self?.afterStop { success in
                    DispatchQueue.main.async {
                        if success {
                            endVC.statusLabel.text = "Data upload succeeded."
                        } else {
                            endVC.statusLabel.text = "Data upload failed."
                        }
                        endVC.closeButton.isHidden = false
                    }
                }
            }
        }
    }

    private func beforeStart() {
        debug("Benchmark.beforeStart()")
        instruments.forEach { $0.beforeStart(scenario: scenario) }
    }

    private func start() {
        debug("Benchmark.start()")
        isRunning = true
        instruments.forEach { $0.start() }
    }

    private func stop() {
        debug("Benchmark.stop()")
        isRunning = false
        instruments.forEach { $0.stop() }
    }

    private func afterStop(completion: @escaping (Bool) -> Void) {
        debug("Benchmark.afterStop()")

        var instrumentResults: [Bool] = []

        let group = DispatchGroup()
        instruments.forEach { instrument in
            group.enter()
            instrument.afterStop(scenario: scenario) { result in
                DispatchQueue.main.async {
                    instrumentResults.append(result)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let result = instrumentResults.reduce(true, { current, next in current && next })
            completion(result)
        }
    }
}
