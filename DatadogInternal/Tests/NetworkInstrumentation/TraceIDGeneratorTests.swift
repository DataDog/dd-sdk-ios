/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class TraceIDGeneratorTests: XCTestCase {
    func testDefaultGenerationBoundaries() {
        let generator = DefaultTraceIDGenerator()
        XCTAssertEqual(generator.range.lowerBound, 1)
        XCTAssertEqual(generator.range.upperBound, 18_446_744_073_709_551_615)
    }

    func testItGeneratesUUIDsFromGivenBoundaries() {
        let generator = DefaultTraceIDGenerator(range: 10...15)

        let lowerBound = UInt32(Date().timeIntervalSince1970)
        (0..<1_000).forEach { _ in
            let id = generator.generate()
            let upperBound = UInt32(Date().timeIntervalSince1970)

            XCTAssertGreaterThanOrEqual(id.idLo, 10)
            XCTAssertLessThanOrEqual(id.idLo, 15)

            let idHiStr = String(id.idHi, radix: 10)
            let idHi = UInt64(idHiStr) ?? 0

            let seconds = UInt32(idHi >> 32)
            XCTAssertGreaterThanOrEqual(seconds, lowerBound)
            XCTAssertLessThanOrEqual(seconds, upperBound)

            let zeros = UInt32(idHi & 0xFFFFFFFF)
            XCTAssertEqual(zeros, 0)
        }
    }
}
