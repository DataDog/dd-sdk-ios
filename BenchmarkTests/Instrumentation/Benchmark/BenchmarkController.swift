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

    private init(scenario: BenchmarkScenario) {
        self.instruments = scenario.instruments()
        self.scenario = scenario
    }

    // MARK: - Control

    static func set(scenario: BenchmarkScenario) {
        precondition(current == nil, "Previous benchmark must end before starting a new one")
        current = BenchmarkController(scenario: scenario)
    }

    static func run() {
        current?.run()
    }

    func startMeasurements() {
        precondition(!scenario.startMeasurementsAutomatically, "Measurements for this scenario will start automatically")
        startInstruments()
    }

    private func run() {
        let app = UIApplication.shared.delegate as! AppDelegate
        setUpInstruments()
        scenario.setUp()

        let scenarioVC = scenario.instantiateInitialViewController()
        let autoStart = scenario.startMeasurementsAutomatically
        app.show(viewController: scenarioVC) { [weak self] in
            if autoStart {
                self?.startInstruments()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + scenario.duration) { [weak self] in
            self?.stopInstruments()
            self?.scenario.tearDown()

            let endVC = UIStoryboard.main.instantiateViewController(withIdentifier: BenchmarkEndViewController.storyboardID) as! BenchmarkEndViewController
            endVC.loadViewIfNeeded()
            endVC.statusLabel.text = "Uploading data..."
            endVC.detailsLabel.text = "Scenario: \(self?.scenario.title ?? "???")"
            endVC.closeButton.isHidden = true
            endVC.onClose = {
                app.goBackToMenu {
                    BenchmarkController.current = nil
                }
            }
            app.show(viewController: endVC) { [weak self] in
                self?.tearDownInstruments { success in
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

    private func setUpInstruments() {
        debug("Benchmark.setUpInstruments()")
        instruments.forEach { $0.beforeStart(scenario: scenario) }
    }

    private func startInstruments() {
        debug("Benchmark.startInstruments()")
        instruments.forEach { $0.start() }
    }

    private func stopInstruments() {
        debug("Benchmark.stopInstruments()")
        instruments.forEach { $0.stop() }
    }

    private func tearDownInstruments(completion: @escaping (Bool) -> Void) {
        debug("Benchmark.tearDownInstruments()")

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
