/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import XCTest
@testable import DatadogTimeseries

final class TimeseriesEncoderTests: XCTestCase {
    func testProducesSortedKeys() throws {
        let event = makeSimpleEvent()
        let encoder = TimeseriesEncoder()
        let data = try encoder.encode(event)
        let json = String(data: data, encoding: .utf8)!

        // _dd should come before application (underscore sorts first in ASCII)
        let ddRange = json.range(of: "\"_dd\"")!
        let appRange = json.range(of: "\"application\"")!
        XCTAssertTrue(ddRange.lowerBound < appRange.lowerBound, "Keys should be sorted")
    }

    func testProducesSnakeCaseKeys() throws {
        let event = makeSimpleEvent()
        let encoder = TimeseriesEncoder()
        let data = try encoder.encode(event)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"format_version\""))
        XCTAssertTrue(json.contains("\"data_point\""))
        XCTAssertFalse(json.contains("\"formatVersion\""))
        XCTAssertFalse(json.contains("\"dataPoint\""))
    }

    func testProducesValidJSON() throws {
        let event = makeSimpleEvent()
        let encoder = TimeseriesEncoder()
        let data = try encoder.encode(event)

        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [String: Any])
    }

    func testDeterministicOutput() throws {
        let event = makeSimpleEvent()
        let encoder = TimeseriesEncoder()
        let data1 = try encoder.encode(event)
        let data2 = try encoder.encode(event)

        XCTAssertEqual(data1, data2, "Encoding the same event should produce identical bytes")
    }

    // MARK: - Helpers

    private func makeSimpleEvent() -> TimeseriesEvent {
        TimeseriesEvent(
            dd: TimeseriesEvent.DD(formatVersion: 2),
            application: TimeseriesEvent.Application(id: "app"),
            date: 1000,
            session: TimeseriesEvent.Session(id: "sess", type: "user"),
            source: "ios",
            type: "timeseries",
            service: nil,
            version: nil,
            timeseries: TimeseriesEvent.Timeseries(
                id: "ts-id",
                name: .memoryUsage,
                start: 1_000_000_000,
                end: 2_000_000_000,
                data: [
                    TimeseriesEvent.DataPoint(timestamp: 1_000_000_000, dataPoint: ["memory_usage": 42]),
                ]
            )
        )
    }
}
