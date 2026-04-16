import XCTest
@testable import DatadogTimeseries

final class WindowAggregateFilterTests: XCTestCase {
    private let windowDuration: Int64 = 3_000_000_000 // 3s

    func testDoesNotEmitUntilWindowCloses() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)
        let result1 = filter.process(Sample(timestamp: 0, value: 10.0))
        let result2 = filter.process(Sample(timestamp: 1_000_000_000, value: 20.0))

        XCTAssertTrue(result1.isEmpty)
        XCTAssertTrue(result2.isEmpty)
    }

    func testEmitsWhenWindowCloses() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)
        _ = filter.process(Sample(timestamp: 0, value: 10.0))
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 20.0))
        // 3rd sample at 4s crosses the 3s boundary
        let result = filter.process(Sample(timestamp: 4_000_000_000, value: 30.0))

        XCTAssertEqual(result.count, 1)
    }

    func testEmittedTimestampIsStartOfWindow() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)
        let firstTimestamp: Int64 = 1_000_000_000
        _ = filter.process(Sample(timestamp: firstTimestamp, value: 10.0))
        _ = filter.process(Sample(timestamp: 2_000_000_000, value: 20.0))
        let result = filter.process(Sample(timestamp: 5_000_000_000, value: 30.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].timestamp, firstTimestamp)
    }

    func testFlushEmitsPartialWindow() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)
        _ = filter.process(Sample(timestamp: 0, value: 10.0))
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 20.0))

        let result = filter.flush()

        XCTAssertEqual(result.count, 1)
    }

    func testFlushOnEmptyBufferReturnsNothing() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)

        let result = filter.flush()

        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleWindowsEachEmitOnce() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration)
        _ = filter.process(Sample(timestamp: 0, value: 10.0))
        // First window closes
        let result1 = filter.process(Sample(timestamp: 3_000_000_000, value: 20.0))
        // Second window closes
        let result2 = filter.process(Sample(timestamp: 6_000_000_000, value: 30.0))

        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result2.count, 1)
    }

    func testAvgAggregate() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration, function: .avg)
        _ = filter.process(Sample(timestamp: 0, value: 10.0))
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 30.0))
        let result = filter.process(Sample(timestamp: 4_000_000_000, value: 0.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 20.0, accuracy: 0.001)
    }

    func testMinAggregate() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration, function: .min)
        _ = filter.process(Sample(timestamp: 0, value: 50.0))
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 20.0))
        _ = filter.process(Sample(timestamp: 2_000_000_000, value: 80.0))
        let result = filter.process(Sample(timestamp: 4_000_000_000, value: 0.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 20.0, accuracy: 0.001)
    }

    func testMaxAggregate() {
        let filter = WindowAggregateFilter(windowDuration: windowDuration, function: .max)
        _ = filter.process(Sample(timestamp: 0, value: 50.0))
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 20.0))
        _ = filter.process(Sample(timestamp: 2_000_000_000, value: 80.0))
        let result = filter.process(Sample(timestamp: 4_000_000_000, value: 0.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 80.0, accuracy: 0.001)
    }
}
