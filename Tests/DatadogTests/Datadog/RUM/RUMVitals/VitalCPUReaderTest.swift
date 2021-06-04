/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class VitalCPUReaderTest: XCTestCase {
    let cpuReader = VitalCPUReader()

    func testWhenCPUUnderHeavyLoad() throws {
        let lowLoadAverage = try averageCPUTicks {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let highLoadAverage = try averageCPUTicks {
            var bigFloatingPoint = Double.greatestFiniteMagnitude
            for _ in 0...1_000 {
                bigFloatingPoint.formSquareRoot()
            }
        }

        // TODO: RUMM-1276 highLoadAverage sometimes becomes 0.0,
        // PR will stay as draft until fixing this
        XCTAssertGreaterThan(highLoadAverage, lowLoadAverage)
    }

    private func averageCPUTicks(with block: () -> Void) throws -> Double {
        let startDate = Date()

        let startCPUTicks = try XCTUnwrap(cpuReader.readVitalData())
        block()
        let endCPUTicks = try XCTUnwrap(cpuReader.readVitalData())
        let duration = Date().timeIntervalSince(startDate)

        let averageCPUTicks = (endCPUTicks - startCPUTicks) / duration

        return averageCPUTicks
    }
}
