import XCTest
@testable import DatadogTimeseries

final class EndToEndVerificationTests: XCTestCase {
    private let config = TimeseriesConfig(
        applicationId: "00000000-0000-0000-0000-000000000000",
        sessionId: "00000000-0000-0000-0000-000000000000",
        sessionType: "user",
        source: "ios",
        service: nil,
        version: nil
    )

    // MARK: - Memory

    func testMemoryBatch1MatchesFixture() throws {
        let actual = try processMetric(.memoryUsage, batchIndex: 0)
        let expected = try loadFixture("expected_memory_batch1")
        XCTAssertEqual(actual, expected, "Memory batch 1 does not match fixture")
    }

    func testMemoryBatch2MatchesFixture() throws {
        let actual = try processMetric(.memoryUsage, batchIndex: 1)
        let expected = try loadFixture("expected_memory_batch2")
        XCTAssertEqual(actual, expected, "Memory batch 2 does not match fixture")
    }

    // MARK: - CPU

    func testCPUBatch1MatchesFixture() throws {
        let actual = try processMetric(.cpuUsage, batchIndex: 0)
        let expected = try loadFixture("expected_cpu_batch1")
        XCTAssertEqual(actual, expected, "CPU batch 1 does not match fixture")
    }

    func testCPUBatch2MatchesFixture() throws {
        let actual = try processMetric(.cpuUsage, batchIndex: 1)
        let expected = try loadFixture("expected_cpu_batch2")
        XCTAssertEqual(actual, expected, "CPU batch 2 does not match fixture")
    }

    // MARK: - Structural validation

    func testOutputContainsRequiredFields() throws {
        let results = try runPipeline(metric: .memoryUsage)
        for data in results {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(json["_dd"])
            XCTAssertNotNil(json["application"])
            XCTAssertNotNil(json["date"])
            XCTAssertNotNil(json["session"])
            XCTAssertNotNil(json["source"])
            XCTAssertNotNil(json["timeseries"])
            XCTAssertEqual(json["type"] as? String, "timeseries")

            let dd = try XCTUnwrap(json["_dd"] as? [String: Any])
            XCTAssertEqual(dd["format_version"] as? Int, 2)

            let session = try XCTUnwrap(json["session"] as? [String: Any])
            XCTAssertEqual(session["type"] as? String, "user")
        }
    }

    func testMemoryProducesTwoBatches() throws {
        let results = try runPipeline(metric: .memoryUsage)
        XCTAssertEqual(results.count, 2, "10 samples / batchSize 5 = 2 batches")
    }

    func testCPUProducesTwoBatches() throws {
        let results = try runPipeline(metric: .cpuUsage)
        XCTAssertEqual(results.count, 2, "10 samples / batchSize 5 = 2 batches")
    }

    // MARK: - Helpers

    private func runPipeline(metric: TimeseriesName) throws -> [Data] {
        let csvURL = try XCTUnwrap(
            Bundle.module.url(forResource: "input_memory_cpu", withExtension: "csv", subdirectory: "Fixtures")
        )
        let csvContent = try String(contentsOf: csvURL)
        let provider = CSVDataProvider(csvContent: csvContent, metric: metric)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: metric,
            batchSize: 5
        )
        return try pipeline.processAll()
    }

    private func processMetric(_ metric: TimeseriesName, batchIndex: Int) throws -> String {
        let results = try runPipeline(metric: metric)
        let jsonString = String(data: results[batchIndex], encoding: .utf8)!
        return maskUUIDs(jsonString)
    }

    private func loadFixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func maskUUIDs(_ string: String) -> String {
        let pattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(
            in: string,
            range: range,
            withTemplate: "00000000-0000-0000-0000-000000000000"
        )
    }
}
