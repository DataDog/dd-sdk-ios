import XCTest
@testable import DatadogTimeseries

final class TimeseriesPipelineTests: XCTestCase {
    private let config = TimeseriesConfig(
        applicationId: "app-id",
        sessionId: "session-id",
        sessionType: "user",
        source: "ios",
        service: nil,
        version: nil
    )

    func testProcessAllProducesCorrectNumberOfBatches() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,100
        2000000000,memory_usage,200
        3000000000,memory_usage,300
        4000000000,memory_usage,400
        5000000000,memory_usage,500
        6000000000,memory_usage,600
        7000000000,memory_usage,700
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 3
        )

        let results = try pipeline.processAll()
        // 7 samples / 3 batch size = 2 full batches + 1 remaining batch (1 sample)
        XCTAssertEqual(results.count, 3)
    }

    func testProcessAllProducesValidJSON() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,100
        2000000000,memory_usage,200
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 5
        )

        let results = try pipeline.processAll()
        // 2 samples < batchSize 5 → 1 remaining batch
        XCTAssertEqual(results.count, 1)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: results[0]) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "timeseries")
    }

    func testEmptyProviderProducesNoOutput() throws {
        let csv = "timestamp,metric,value\n"
        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 5
        )

        let results = try pipeline.processAll()
        XCTAssertTrue(results.isEmpty)
    }
}
