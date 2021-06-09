/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit.UIApplication
@testable import Datadog

class VitalCPUReaderTest: XCTestCase {
    let testNotificationCenter = NotificationCenter()
    lazy var cpuReader = VitalCPUReader(notificationCenter: testNotificationCenter)

    func test_whenCPUUnderHeavyLoad_itMeasuresHigherCPUTicks() throws {
        let highLoadAverage = try averageCPUTicks {
            for _ in 0...500_000 {
                let random = Double.random(in: Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
                _ = tan(random).squareRoot()
            }
        }

        let lowLoadAverage = try averageCPUTicks {
            Thread.sleep(forTimeInterval: 1.0)
        }

        XCTAssertGreaterThan(highLoadAverage, lowLoadAverage)
    }

    func test_whenInactiveAppState_itIggnoresCPUTicks() throws {
        let heavyLoad = {
            for _ in 0...500_000 {
                let random = Double.random(in: Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
                _ = tan(random).squareRoot()
            }
        }

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
