/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class SpanIDGeneratorTests: XCTestCase {
    func testDefaultGenerationBoundaries() {
        let generator = DefaultSpanIDGenerator()
        XCTAssertEqual(generator.range.lowerBound, 1)
        XCTAssertEqual(generator.range.upperBound, 9_223_372_036_854_775_807) // 2 ^ 63 -1
    }

    func testItGeneratesUUIDsFromGivenBoundaries() {
        let generator = DefaultSpanIDGenerator(range: 10...15)
        var generatedUUIDs: Set<SpanID> = []

        (0..<1_000).forEach { _ in
            generatedUUIDs.insert(generator.generate())
        }

        XCTAssertEqual(generatedUUIDs, [10, 11, 12, 13, 14, 15])
    }
}

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

            // take 8 characters from the right
            let idHiRight = idHiStr.suffix(8)
            let zeros = UInt32(idHiRight, radix: 10)
            XCTAssertEqual(zeros, 0)

            // take 8 characters from right after the first 8
            let idHiLeft = idHiStr.prefix(idHiStr.count - 8)
            let seconds = UInt32(idHiLeft, radix: 10)!
            XCTAssertGreaterThanOrEqual(seconds, lowerBound)
            XCTAssertLessThanOrEqual(seconds, upperBound)
        }
    }
}
