/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import XCTest
@testable import DatadogTimeseries

final class PassThroughFilterTests: XCTestCase {
    func testPassesEverySampleThrough() {
        let filter = PassThroughFilter()
        let sample = Sample(timestamp: 1_000_000_000, value: 42.0)

        let result = filter.process(sample)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].timestamp, sample.timestamp)
        XCTAssertEqual(result[0].value, sample.value)
    }

    func testPassesAllConsecutiveSamples() {
        let filter = PassThroughFilter()
        let samples = [
            Sample(timestamp: 1_000_000_000, value: 10.0),
            Sample(timestamp: 2_000_000_000, value: 20.0),
            Sample(timestamp: 3_000_000_000, value: 30.0),
        ]

        let result = samples.flatMap { filter.process($0) }

        XCTAssertEqual(result.count, 3)
    }

    func testFlushReturnsEmptyArray() {
        let filter = PassThroughFilter()

        let result = filter.flush()

        XCTAssertTrue(result.isEmpty)
    }
}
