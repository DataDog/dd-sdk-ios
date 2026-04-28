import XCTest
@testable import DatadogTimeseries

final class SkipSampleTests: XCTestCase {
    private let config = TimeseriesConfig(
        applicationId: "app-id",
        sessionId: "session-id",
        sessionType: "user",
        source: "ios",
        service: nil,
        version: nil
    )

    func testGapInCSVProducesFewerDataPoints() throws {
        // 5 rows but only 3 are memory_usage (gap at timestamps 2 and 4)
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,100
        2000000000,cpu_usage,10
        3000000000,memory_usage,300
        4000000000,cpu_usage,20
        5000000000,memory_usage,500
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 5
        )

        let results = try pipeline.processAll()
        XCTAssertEqual(results.count, 1) // 3 samples < batchSize 5 → 1 remaining batch

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: results[0]) as? [String: Any])
        let ts = try XCTUnwrap(json["timeseries"] as? [String: Any])
        let data = try XCTUnwrap(ts["data"] as? [[String: Any]])

        XCTAssertEqual(data.count, 3, "Only 3 memory_usage samples, gap reflected")
        XCTAssertEqual(data[0]["timestamp"] as? Int64, 1000000000)
        XCTAssertEqual(data[1]["timestamp"] as? Int64, 3000000000) // gap: 2s jumped
        XCTAssertEqual(data[2]["timestamp"] as? Int64, 5000000000)
    }

    func testMalformedRowsSkipped() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,100
        not_a_number,memory_usage,bad
        3000000000,memory_usage,300
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 5
        )

        let results = try pipeline.processAll()
        XCTAssertEqual(results.count, 1)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: results[0]) as? [String: Any])
        let ts = try XCTUnwrap(json["timeseries"] as? [String: Any])
        let data = try XCTUnwrap(ts["data"] as? [[String: Any]])

        XCTAssertEqual(data.count, 2, "Malformed row skipped")
    }

    func testTimestampsReflectGap() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,100
        5000000000,memory_usage,500
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 5
        )

        let results = try pipeline.processAll()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: results[0]) as? [String: Any])
        let ts = try XCTUnwrap(json["timeseries"] as? [String: Any])

        XCTAssertEqual(ts["start"] as? Int64, 1000000000)
        XCTAssertEqual(ts["end"] as? Int64, 5000000000)
    }
}
