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
        XCTAssertEqual(generator.range.upperBound, 9_223_372_036_854_775_807) // 2 ^ 63 -1
    }

    func testItGeneratesUUIDsFromGivenBoundaries() {
        let generator = DefaultTraceIDGenerator(range: 10...15)
        var generatedUUIDs: Set<TraceID> = []

        (0..<1_000).forEach { _ in
            generatedUUIDs.insert(generator.generate())
        }

        XCTAssertEqual(generatedUUIDs, [10, 11, 12, 13, 14, 15])
    }
}
