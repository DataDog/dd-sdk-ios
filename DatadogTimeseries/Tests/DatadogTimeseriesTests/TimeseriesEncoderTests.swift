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
        XCTAssertTrue(json.contains("\"data_point_value\""))
        XCTAssertFalse(json.contains("\"formatVersion\""))
        XCTAssertFalse(json.contains("\"dataPointValue\""))
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
                    TimeseriesEvent.DataPoint(timestamp: 1_000_000_000, dataPointValue: 42),
                ]
            )
        )
    }
}
