import XCTest
@testable import DatadogTimeseries

final class DeadbandFilterTests: XCTestCase {
    func testAlwaysEmitsFirstSample() {
        let filter = DeadbandFilter(threshold: 10.0)
        let sample = Sample(timestamp: 1_000_000_000, value: 50.0)

        let result = filter.process(sample)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 50.0)
    }

    func testSuppressesSampleBelowThreshold() {
        let filter = DeadbandFilter(threshold: 10.0)
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 50.0))

        let result = filter.process(Sample(timestamp: 2_000_000_000, value: 55.0))

        XCTAssertTrue(result.isEmpty)
    }

    func testEmitsAtExactThreshold() {
        let filter = DeadbandFilter(threshold: 10.0)
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 50.0))

        let result = filter.process(Sample(timestamp: 2_000_000_000, value: 60.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 60.0)
    }

    func testEmitsOnNegativeDelta() {
        let filter = DeadbandFilter(threshold: 10.0)
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 50.0))

        let result = filter.process(Sample(timestamp: 2_000_000_000, value: 35.0))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 35.0)
    }

    func testReferencesLastEmittedNotLastSeen() {
        let filter = DeadbandFilter(threshold: 10.0)
        // Emit at 50
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 50.0))
        // Suppress 54 (diff from 50 = 4)
        let suppress1 = filter.process(Sample(timestamp: 2_000_000_000, value: 54.0))
        // Suppress 58 (diff from 50 = 8, not from 54)
        let suppress2 = filter.process(Sample(timestamp: 3_000_000_000, value: 58.0))
        // Emit 61 (diff from 50 = 11)
        let emit = filter.process(Sample(timestamp: 4_000_000_000, value: 61.0))

        XCTAssertTrue(suppress1.isEmpty)
        XCTAssertTrue(suppress2.isEmpty)
        XCTAssertEqual(emit.count, 1)
        XCTAssertEqual(emit[0].value, 61.0)
    }

    func testHeartbeatFiresAfterSilenceInterval() {
        let heartbeat: Int64 = 5_000_000_000 // 5s
        let filter = DeadbandFilter(threshold: 10.0, heartbeatInterval: heartbeat)
        // Emit first sample at t=0
        _ = filter.process(Sample(timestamp: 0, value: 50.0))
        // Suppress at t=3s (value barely moved, not past heartbeat)
        let suppress = filter.process(Sample(timestamp: 3_000_000_000, value: 51.0))
        // Emit at t=6s (heartbeat due, even though value barely moved)
        let emit = filter.process(Sample(timestamp: 6_000_000_000, value: 52.0))

        XCTAssertTrue(suppress.isEmpty)
        XCTAssertEqual(emit.count, 1)
        XCTAssertEqual(emit[0].value, 52.0)
    }

    func testNoHeartbeatWithoutIntervalConfigured() {
        let filter = DeadbandFilter(threshold: 10.0)
        _ = filter.process(Sample(timestamp: 0, value: 50.0))

        // 60s later, value barely moved — no heartbeat configured
        let result = filter.process(Sample(timestamp: 60_000_000_000, value: 51.0))

        XCTAssertTrue(result.isEmpty)
    }

    func testFlushReturnsNothing() {
        let filter = DeadbandFilter(threshold: 10.0)
        _ = filter.process(Sample(timestamp: 1_000_000_000, value: 50.0))

        let result = filter.flush()

        XCTAssertTrue(result.isEmpty)
    }
}
