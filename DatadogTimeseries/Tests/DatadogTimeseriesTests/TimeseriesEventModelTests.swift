import XCTest
@testable import DatadogTimeseries

final class TimeseriesEventModelTests: XCTestCase {
    func testTimeseriesEventEncodesToExpectedJSON() throws {
        let event = TimeseriesEvent(
            dd: TimeseriesEvent.DD(formatVersion: 2),
            application: TimeseriesEvent.Application(id: "app-id-123"),
            date: 1773055119487,
            session: TimeseriesEvent.Session(id: "session-id-456", type: "user"),
            source: "ios",
            type: "timeseries",
            service: "my-service",
            version: "1.0.0",
            timeseries: TimeseriesEvent.Timeseries(
                id: "ts-id-789",
                name: .memoryUsage,
                start: 1773055068831000000,
                end: 1773055082916000000,
                data: [
                    TimeseriesEvent.DataPoint(timestamp: 1773055068831000000, dataPointValue: 38052032),
                    TimeseriesEvent.DataPoint(timestamp: 1773055069917000000, dataPointValue: 37970112),
                ]
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Root-level fields
        let dd = try XCTUnwrap(json["_dd"] as? [String: Any])
        XCTAssertEqual(dd["format_version"] as? Int, 2)

        let application = try XCTUnwrap(json["application"] as? [String: Any])
        XCTAssertEqual(application["id"] as? String, "app-id-123")

        XCTAssertEqual(json["date"] as? Int64, 1773055119487)

        let session = try XCTUnwrap(json["session"] as? [String: Any])
        XCTAssertEqual(session["id"] as? String, "session-id-456")
        XCTAssertEqual(session["type"] as? String, "user")

        XCTAssertEqual(json["source"] as? String, "ios")
        XCTAssertEqual(json["type"] as? String, "timeseries")
        XCTAssertEqual(json["service"] as? String, "my-service")
        XCTAssertEqual(json["version"] as? String, "1.0.0")

        // Timeseries nested object
        let ts = try XCTUnwrap(json["timeseries"] as? [String: Any])
        XCTAssertEqual(ts["id"] as? String, "ts-id-789")
        XCTAssertEqual(ts["name"] as? String, "memory_usage")
        XCTAssertEqual(ts["start"] as? Int64, 1773055068831000000)
        XCTAssertEqual(ts["end"] as? Int64, 1773055082916000000)

        let dataPoints = try XCTUnwrap(ts["data"] as? [[String: Any]])
        XCTAssertEqual(dataPoints.count, 2)
        XCTAssertEqual(dataPoints[0]["timestamp"] as? Int64, 1773055068831000000)
        XCTAssertEqual(dataPoints[0]["data_point_value"] as? Double, 38052032)
    }

    func testTimeseriesEventOmitsNilServiceAndVersion() throws {
        let event = TimeseriesEvent(
            dd: TimeseriesEvent.DD(formatVersion: 2),
            application: TimeseriesEvent.Application(id: "app-id"),
            date: 1000,
            session: TimeseriesEvent.Session(id: "sess-id", type: "user"),
            source: "ios",
            type: "timeseries",
            service: nil,
            version: nil,
            timeseries: TimeseriesEvent.Timeseries(
                id: "ts-id",
                name: .cpuUsage,
                start: 1000000000,
                end: 2000000000,
                data: [
                    TimeseriesEvent.DataPoint(timestamp: 1000000000, dataPointValue: 55.3),
                ]
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["service"])
        XCTAssertNil(json["version"])
        XCTAssertEqual(json["type"] as? String, "timeseries")

        let ts = try XCTUnwrap(json["timeseries"] as? [String: Any])
        XCTAssertEqual(ts["name"] as? String, "cpu_usage")
    }

    func testTimeseriesNameRawValues() {
        XCTAssertEqual(TimeseriesName.memoryUsage.rawValue, "memory_usage")
        XCTAssertEqual(TimeseriesName.cpuUsage.rawValue, "cpu_usage")
    }

    func testSampleStoresValues() {
        let sample = Sample(timestamp: 5_000_000_000, value: 123.456)
        XCTAssertEqual(sample.timestamp, 5_000_000_000)
        XCTAssertEqual(sample.value, 123.456)
    }
}
