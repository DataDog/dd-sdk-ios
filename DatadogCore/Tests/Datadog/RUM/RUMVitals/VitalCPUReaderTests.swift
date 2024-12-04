/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit.UIApplication
@testable import DatadogRUM

class VitalCPUReaderTest: XCTestCase {
    let testNotificationCenter = NotificationCenter()
    lazy var cpuReader = VitalCPUReader(notificationCenter: testNotificationCenter)

    func testWhenCPUUnderHeavyLoadItMeasuresHigherCPUTicks() throws {
        let repetitions = 3

        // The CPU ticks consumed during heavy processing are not always greater than those during light processing.
        // System variables can influence these results, leading to potential inaccuracies.
        // To minimize false positives, an average is calculated over n repetitions.
        let utilizationArray: [(highUtilization: Double, sleepUtilization: Double)] = try (0..<repetitions).map { _ in
            // calculates the utilization under heavy processing
            let highLoadResult = try utilizationAndDuration(heavyLoad)

            let sleepResult = try utilizationAndDuration {
                // The sleep duration should be the same as the heavy load duration
                Thread.sleep(forTimeInterval: highLoadResult.duration)
            }

            return (highLoadResult.utilization, sleepResult.utilization)
        }

        let totalUtilization = utilizationArray.reduce((highUtilization: 0.0, sleepUtilization: 0.0)) {
            ($0.highUtilization + $1.highUtilization,  $0.sleepUtilization + $1.sleepUtilization)
        }

        XCTAssertGreaterThan(totalUtilization.highUtilization / Double(repetitions), totalUtilization.sleepUtilization / Double(repetitions))
    }

    func testWhenInactiveAppStateItIgnoresCPUTicks() throws {
        let baseline = try XCTUnwrap(cpuReader.readVitalData())
        testNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        heavyLoad()
        let measurementWhenInactive = try XCTUnwrap(cpuReader.readVitalData())
        testNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        heavyLoad()
        let measurementWhenActive = try XCTUnwrap(cpuReader.readVitalData())

        let diffWhenInactive = measurementWhenInactive - baseline
        let diffWhenActive = measurementWhenActive - measurementWhenInactive

        XCTAssertGreaterThan(diffWhenActive, diffWhenInactive)
    }

    private func utilizationAndDuration(_ block: () -> Void) throws -> (utilization: Double, duration: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startUtilization = try XCTUnwrap(cpuReader.readVitalData())

        block()

        let endUtilization = try XCTUnwrap(cpuReader.readVitalData())
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        let utilizedTicks = endUtilization - startUtilization

        return (utilizedTicks / duration, duration)
    }
}

fileprivate func heavyLoad() {
    // cpuTicksResolution is measured by trial&error.
    // most of the time `readVitalData()` returns incremented data after 0.01sec.
    // however, sometimes it returns the same value for 1.0sec.
    // looking at the source code, iOS should update cpu ticks at
    // every thread scheduling and/or system->user/user->system mode changes in CPU.
    // but empirically, it gets stuck for 1.0sec randomly.
    let worstCaseCPUTicksResolution: TimeInterval = 1.0
    let startDate = Date()

    while Date().timeIntervalSince(startDate) <= worstCaseCPUTicksResolution {
        for _ in 0...100_000 {
            let random = Double.random(in: Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
            _ = tan(random).squareRoot()
        }
    }
}
