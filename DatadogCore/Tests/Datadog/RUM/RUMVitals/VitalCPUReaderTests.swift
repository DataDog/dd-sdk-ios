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
        let highLoadAverage = try averageCPUTicks {
            heavyLoad()
        }

        let lowLoadAverage = try averageCPUTicks {
            Thread.sleep(forTimeInterval: 1.0)
        }

        XCTAssertGreaterThan(highLoadAverage, lowLoadAverage)
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

    private func averageCPUTicks(with block: () -> Void) throws -> Double {
        let startDate = Date()
        let startUtilization = try XCTUnwrap(cpuReader.readVitalData())

        block()

        let endUtilization = try XCTUnwrap(cpuReader.readVitalData())
        let duration = Date().timeIntervalSince(startDate)

        let utilizedTicks = endUtilization - startUtilization
        let utilization = utilizedTicks / duration

        return utilization
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
