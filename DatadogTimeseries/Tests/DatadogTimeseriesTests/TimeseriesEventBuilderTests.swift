/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import XCTest
@testable import DatadogTimeseries

final class TimeseriesEventBuilderTests: XCTestCase {
    private let config = TimeseriesConfig(
        applicationId: "app-123",
        sessionId: "session-456",
        sessionType: "user",
        source: "ios",
        service: "test-service",
        version: "2.0.0"
    )

    func testBuildsEventWithCorrectEnvelope() {
        let builder = TimeseriesEventBuilder(config: config)
        let samples = [
            Sample(timestamp: 5_000_000_000, value: 100),
            Sample(timestamp: 6_000_000_000, value: 200),
        ]

        let event = builder.build(samples: samples, name: .memoryUsage, eventId: "evt-id")

        XCTAssertEqual(event.dd.formatVersion, 2)
        XCTAssertEqual(event.application.id, "app-123")
        XCTAssertEqual(event.session.id, "session-456")
        XCTAssertEqual(event.session.type, "user")
        XCTAssertEqual(event.source, "ios")
        XCTAssertEqual(event.type, "timeseries")
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "2.0.0")
    }

    func testBuildsEventWithCorrectTimeseries() {
        let builder = TimeseriesEventBuilder(config: config)
        let samples = [
            Sample(timestamp: 5_000_000_000, value: 100),
            Sample(timestamp: 6_000_000_000, value: 200),
            Sample(timestamp: 7_000_000_000, value: 300),
        ]

        let event = builder.build(samples: samples, name: .cpuUsage, eventId: "my-uuid")

        XCTAssertEqual(event.timeseries.id, "my-uuid")
        XCTAssertEqual(event.timeseries.name, .cpuUsage)
        XCTAssertEqual(event.timeseries.start, 5_000_000_000)
        XCTAssertEqual(event.timeseries.end, 7_000_000_000)
        XCTAssertEqual(event.timeseries.data.count, 3)
    }

    func testDateIsStartTimestampConvertedToMilliseconds() {
        let builder = TimeseriesEventBuilder(config: config)
        let samples = [
            Sample(timestamp: 1_773_055_068_831_000_000, value: 42),
        ]

        let event = builder.build(samples: samples, name: .memoryUsage, eventId: "id")

        // 1_773_055_068_831_000_000 ns / 1_000_000 = 1_773_055_068_831 ms
        XCTAssertEqual(event.date, 1_773_055_068_831)
    }

    func testDataPointsMatchSamples() {
        let builder = TimeseriesEventBuilder(config: config)
        let samples = [
            Sample(timestamp: 1000, value: 42.5),
            Sample(timestamp: 2000, value: 99.9),
        ]

        let event = builder.build(samples: samples, name: .memoryUsage, eventId: "id")

        XCTAssertEqual(event.timeseries.data[0].timestamp, 1000)
        XCTAssertEqual(event.timeseries.data[0].dataPoint["memory_usage"], 42.5)
        XCTAssertEqual(event.timeseries.data[1].timestamp, 2000)
        XCTAssertEqual(event.timeseries.data[1].dataPoint["memory_usage"], 99.9)
    }

    func testNilServiceAndVersion() {
        let configNoOptionals = TimeseriesConfig(
            applicationId: "app",
            sessionId: "sess",
            sessionType: "user",
            source: "ios",
            service: nil,
            version: nil
        )
        let builder = TimeseriesEventBuilder(config: configNoOptionals)
        let event = builder.build(
            samples: [Sample(timestamp: 1, value: 1)],
            name: .cpuUsage,
            eventId: "id"
        )

        XCTAssertNil(event.service)
        XCTAssertNil(event.version)
    }
}
