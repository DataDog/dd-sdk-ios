/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import XCTest
@testable import DatadogTimeseries

final class FilterComparisonTests: XCTestCase {
    private let config = TimeseriesConfig(
        applicationId: "test-app",
        sessionId: "test-session",
        sessionType: "user",
        source: "ios",
        service: nil,
        version: nil
    )

    // MARK: - PassThroughFilter

    func testPassThroughEmitsAllSamples() throws {
        let count = try totalDataPoints(filter: PassThroughFilter(), metric: .memoryUsage)
        XCTAssertEqual(count, 60)
    }

    func testPassThroughCPUEmitsAllSamples() throws {
        let count = try totalDataPoints(filter: PassThroughFilter(), metric: .cpuUsage)
        XCTAssertEqual(count, 60)
    }

    // MARK: - DeadbandFilter

    func testDeadbandReducesMemorySamples() throws {
        let count = try totalDataPoints(filter: DeadbandFilter(threshold: 1_000_000), metric: .memoryUsage)
        XCTAssertLessThan(count, 60)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testDeadbandCapturesAllocationJumps() throws {
        // First sample always emitted + allocation jumps of 1-2 MB each cross the 1 MB threshold
        let count = try totalDataPoints(filter: DeadbandFilter(threshold: 1_000_000), metric: .memoryUsage)
        XCTAssertGreaterThanOrEqual(count, 3)
    }

    // MARK: - WindowAggregateFilter

    func testWindowAggregateReducesCPUSamples() throws {
        // 60 samples at 1s intervals / 5s window = 12 windows
        let count = try totalDataPoints(
            filter: WindowAggregateFilter(windowDuration: 5_000_000_000, function: .max),
            metric: .cpuUsage
        )
        XCTAssertEqual(count, 12)
    }

    func testWindowAggregateTimestampIsWindowStart() throws {
        let csvURL = try XCTUnwrap(
            Bundle.module.url(forResource: "input_realistic_60s", withExtension: "csv", subdirectory: "Fixtures")
        )
        let csvContent = try String(contentsOf: csvURL)

        let filter = WindowAggregateFilter(windowDuration: 5_000_000_000, function: .max)
        let provider = CSVDataProvider(csvContent: csvContent, metric: .cpuUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .cpuUsage,
            batchSize: 100,
            filter: filter
        )

        let results = try pipeline.processAll()
        let firstBatch = try XCTUnwrap(results.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBatch) as? [String: Any])
        let timeseries = try XCTUnwrap(json["timeseries"] as? [String: Any])
        let data = try XCTUnwrap(timeseries["data"] as? [[String: Any]])
        let firstPoint = try XCTUnwrap(data.first)
        let firstTimestamp = try XCTUnwrap(firstPoint["timestamp"] as? Int64)

        // First window starts at the first sample timestamp (nanoseconds)
        XCTAssertEqual(firstTimestamp, 1_700_000_001_000_000_000)
    }

    // MARK: - JSON validity across all filters

    func testAllFiltersProduceValidJSON() throws {
        let filters: [SampleFilter] = [
            PassThroughFilter(),
            DeadbandFilter(threshold: 1_000_000),
            WindowAggregateFilter(windowDuration: 5_000_000_000, function: .max),
        ]

        for filter in filters {
            let csvURL = try XCTUnwrap(
                Bundle.module.url(forResource: "input_realistic_60s", withExtension: "csv", subdirectory: "Fixtures")
            )
            let csvContent = try String(contentsOf: csvURL)
            let provider = CSVDataProvider(csvContent: csvContent, metric: .memoryUsage)
            let pipeline = TimeseriesPipeline(
                provider: provider,
                config: config,
                metricName: .memoryUsage,
                batchSize: 100,
                filter: filter
            )

            let results = try pipeline.processAll()

            for data in results {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["type"] as? String, "timeseries")
                XCTAssertNotNil(json["_dd"])
                let timeseries = try XCTUnwrap(json["timeseries"] as? [String: Any])
                let points = try XCTUnwrap(timeseries["data"] as? [[String: Any]])
                XCTAssertFalse(points.isEmpty)
            }
        }
    }

    // MARK: - Regression guard

    func testPipelineDefaultIsPassThrough() throws {
        // Creates pipeline WITHOUT passing filter arg — verifies default PassThroughFilter behaviour
        let csvURL = try XCTUnwrap(
            Bundle.module.url(forResource: "input_realistic_60s", withExtension: "csv", subdirectory: "Fixtures")
        )
        let csvContent = try String(contentsOf: csvURL)
        let provider = CSVDataProvider(csvContent: csvContent, metric: .memoryUsage)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: .memoryUsage,
            batchSize: 100
        )

        let results = try pipeline.processAll()
        let count = try dataPointCount(in: results)
        XCTAssertEqual(count, 60)
    }

    // MARK: - Helpers

    private func totalDataPoints(filter: SampleFilter, metric: TimeseriesName) throws -> Int {
        let csvURL = try XCTUnwrap(
            Bundle.module.url(forResource: "input_realistic_60s", withExtension: "csv", subdirectory: "Fixtures")
        )
        let csvContent = try String(contentsOf: csvURL)
        let provider = CSVDataProvider(csvContent: csvContent, metric: metric)
        let pipeline = TimeseriesPipeline(
            provider: provider,
            config: config,
            metricName: metric,
            batchSize: 100,
            filter: filter
        )

        let results = try pipeline.processAll()
        return try dataPointCount(in: results)
    }

    private func dataPointCount(in results: [Data]) throws -> Int {
        var total = 0
        for data in results {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let timeseries = try XCTUnwrap(json["timeseries"] as? [String: Any])
            let points = try XCTUnwrap(timeseries["data"] as? [[String: Any]])
            total += points.count
        }
        return total
    }
}
