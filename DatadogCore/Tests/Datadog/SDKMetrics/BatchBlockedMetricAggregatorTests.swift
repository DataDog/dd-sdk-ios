/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class BatchBlockedMetricAggregatorTests: XCTestCase {
    func testFailureIncrement() throws {
        // Given
        let aggregator = BatchBlockedMetricAggregator()

        let track1: String = .mockRandom()
        let failure1: String = .mockRandom()

        let track2: String = .mockRandom()
        let failure2: String = .mockRandom()

        let iterations: Int = .mockRandom(min: 0, max: 100)

        // When
        for _ in 0..<iterations {
            aggregator.increment(by: 1, track: track1, failure: failure1)
            aggregator.increment(by: 1, track: track2, failure: failure2)
        }

        // Then
        let attributes = aggregator.flush()
        XCTAssertEqual(attributes.count, 2)

        let metric1 = try XCTUnwrap(attributes.first(where: { track1 == $0.attributes["track"] as? String }))
        XCTAssertEqual(metric1.attributes["count"] as? Int, iterations)
        XCTAssertEqual(metric1.attributes["failure"] as? String, failure1)
        XCTAssertNil(metric1.attributes["blockers"])

        let metric2 = try XCTUnwrap(attributes.first(where: { track2 == $0.attributes["track"] as? String }))
        XCTAssertEqual(metric2.attributes["count"] as? Int, iterations)
        XCTAssertEqual(metric2.attributes["failure"] as? String, failure2)
        XCTAssertNil(metric2.attributes["blockers"])

        XCTAssertTrue(aggregator.flush().isEmpty)
    }

    func testBlockersIncrement() throws {
        // Given
        let aggregator = BatchBlockedMetricAggregator()

        let track1: String = .mockRandom()
        let blockers1: [String] = .mockRandom()

        let track2: String = .mockRandom()
        let blockers2: [String] = .mockRandom()

        let iterations: Int = .mockRandom(min: 0, max: 100)

        // When
        for _ in 0..<iterations {
            aggregator.increment(by: 1, track: track1, blockers: blockers1)
            aggregator.increment(by: 1, track: track2, blockers: blockers2)
        }

        // Then
        let attributes = aggregator.flush()
        XCTAssertEqual(attributes.count, 2)

        let metric1 = try XCTUnwrap(attributes.first(where: { track1 == $0.attributes["track"] as? String }))
        XCTAssertEqual(metric1.attributes["count"] as? Int, iterations)
        XCTAssertEqual(metric1.attributes["blockers"] as? [String], blockers1)
        XCTAssertNil(metric1.attributes["failure"])

        let metric2 = try XCTUnwrap(attributes.first(where: { track2 == $0.attributes["track"] as? String }))
        XCTAssertEqual(metric2.attributes["count"] as? Int, iterations)
        XCTAssertEqual(metric2.attributes["blockers"] as? [String], blockers2)
        XCTAssertNil(metric2.attributes["failure"])

        XCTAssertTrue(aggregator.flush().isEmpty)
    }

    func testConcurrency() throws {
        // Given
        let aggregator = BatchBlockedMetricAggregator()

        let track: String = .mockRandom()
        let blockers: [String] = .mockRandom()
        let failure: String = .mockRandom()

        // Then
        callConcurrently(
            { aggregator.increment(by: 1, track: track, failure: failure) },
            { aggregator.increment(by: 1, track: track, blockers: blockers) },
            { _ = aggregator.flush() }
        )
    }
}
