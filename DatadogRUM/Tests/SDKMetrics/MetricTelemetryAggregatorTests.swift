/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class MetricTelemetryAggregatorTests: XCTestCase {
    func testCounterIncrement() throws {
        // Given
        let aggregator = MetricTelemetryAggregator()

        let metric1: String = .mockRandom()

        let cardinalities1: MetricTelemetry.Cardinalities = [
            .mockRandom(): .string(.mockRandom())
        ]

        let metric2: String = .mockRandom()
        let cardinalities2: MetricTelemetry.Cardinalities = [
            .mockRandom(): .integer(.mockRandom())
        ]

        let iterations: Int = .mockRandom(min: 0, max: 100)

        // When
        for _ in 0..<iterations {
            aggregator.increment(metric1, by: 1, cardinalities: cardinalities1)
            aggregator.increment(metric1, by: 1, cardinalities: cardinalities2)
            aggregator.increment(metric2, by: 1, cardinalities: cardinalities1)
            aggregator.increment(metric2, by: 1, cardinalities: cardinalities2)
        }

        // Then
        let events = aggregator.flush()
        XCTAssertEqual(events.count, 4)

        let event1 = try XCTUnwrap(events.first(where: { metric1 == $0.name }))
        XCTAssertEqual(event1.attributes["value"] as? Double, Double(iterations))

        let event2 = try XCTUnwrap(events.first(where: { metric2 == $0.name }))
        XCTAssertEqual(event2.attributes["value"] as? Double, Double(iterations))

        XCTAssertTrue(aggregator.flush().isEmpty)
    }

    func testGaugeRecord() throws {
        // Given
        let aggregator = MetricTelemetryAggregator()

        let metric1: String = .mockRandom()
        let cardinalities1: MetricTelemetry.Cardinalities = [
            .mockRandom(): .string(.mockRandom())
        ]
        let value1: Double = .mockRandom()

        let metric2: String = .mockRandom()
        let cardinalities2: MetricTelemetry.Cardinalities = [
            .mockRandom(): .integer(.mockRandom())
        ]
        let value2: Double = .mockRandom()

        let iterations: Int = .mockRandom(min: 0, max: 100)

        // When
        for _ in 0..<iterations {
            aggregator.record(metric1, value: value1, cardinalities: cardinalities1)
            aggregator.record(metric1, value: value1, cardinalities: cardinalities2)
            aggregator.record(metric2, value: value2, cardinalities: cardinalities1)
            aggregator.record(metric2, value: value2, cardinalities: cardinalities2)
        }

        // Then
        let events = aggregator.flush()
        XCTAssertEqual(events.count, 4)

        let event1 = try XCTUnwrap(events.first(where: { metric1 == $0.name }))
        XCTAssertEqual(event1.attributes["value"] as? Double, value1)

        let event2 = try XCTUnwrap(events.first(where: { metric2 == $0.name }))
        XCTAssertEqual(event2.attributes["value"] as? Double, value2)

        XCTAssertTrue(aggregator.flush().isEmpty)
    }

    func testConcurrency() throws {
        // Given
        let aggregator = MetricTelemetryAggregator()

        let metric1: String = .mockRandom()
        let metric2: String = .mockRandom()

        // Then
        callConcurrently(
            { aggregator.increment(metric1, by: 1, cardinalities: [:]) },
            { aggregator.record(metric2, value: 1, cardinalities: [:]) },
            { _ = aggregator.flush() }
        )
    }
}
