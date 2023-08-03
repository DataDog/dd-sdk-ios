/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class Benchmark {
    struct Configuration {
        /// For how long this benchmark will be running.
        let expectedDuration: TimeInterval
    }

    let configuration: Configuration
    let instruments: [Instrument]

    init(configuration: Configuration, instruments: [Instrument]) {
        self.configuration = configuration
        self.instruments = instruments
    }

    // MARK: - Control

    private var startDate: Date?

    func beforeStart() {
        debug("Benchmark.beforeStart()")
        instruments.forEach { $0.beforeStart(configuration: configuration) }
    }

    func start() {
        debug("Benchmark.start()")
        startDate = Date()
        instruments.forEach { $0.start() }
    }

    func stop() {
        debug("Benchmark.stop()")
        instruments.forEach { $0.stop() }
    }

    func afterStop() {
        debug("Benchmark.afterStop()")
        instruments.forEach { $0.afterStop() }
    }

    var isStarted: Bool {
        guard let startDate = startDate else {
            return false
        }
        return Date() > startDate.addingTimeInterval(configuration.expectedDuration)
    }
}

internal var benchmark: Benchmark!
