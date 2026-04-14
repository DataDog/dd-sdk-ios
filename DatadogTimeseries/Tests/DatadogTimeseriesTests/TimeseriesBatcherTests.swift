import XCTest
@testable import DatadogTimeseries

final class TimeseriesBatcherTests: XCTestCase {
    func testDoesNotFlushBeforeBatchSize() {
        let batcher = TimeseriesBatcher(batchSize: 3)
        batcher.add(Sample(timestamp: 1, value: 10))
        batcher.add(Sample(timestamp: 2, value: 20))

        XCTAssertFalse(batcher.shouldFlush())
    }

    func testFlushesAtBatchSize() {
        let batcher = TimeseriesBatcher(batchSize: 3)
        batcher.add(Sample(timestamp: 1, value: 10))
        batcher.add(Sample(timestamp: 2, value: 20))
        batcher.add(Sample(timestamp: 3, value: 30))

        XCTAssertTrue(batcher.shouldFlush())

        let batch = batcher.flush()
        XCTAssertEqual(batch.count, 3)
        XCTAssertEqual(batch[0].timestamp, 1)
        XCTAssertEqual(batch[1].timestamp, 2)
        XCTAssertEqual(batch[2].timestamp, 3)
    }

    func testFlushClearsBuffer() {
        let batcher = TimeseriesBatcher(batchSize: 2)
        batcher.add(Sample(timestamp: 1, value: 10))
        batcher.add(Sample(timestamp: 2, value: 20))

        _ = batcher.flush()

        XCTAssertFalse(batcher.shouldFlush())
        XCTAssertTrue(batcher.flush().isEmpty)
    }

    func testFlushRemainingReturnsSamples() {
        let batcher = TimeseriesBatcher(batchSize: 5)
        batcher.add(Sample(timestamp: 1, value: 10))
        batcher.add(Sample(timestamp: 2, value: 20))

        let remaining = batcher.flushRemaining()
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining?.count, 2)
    }

    func testFlushRemainingReturnsNilWhenEmpty() {
        let batcher = TimeseriesBatcher(batchSize: 5)
        XCTAssertNil(batcher.flushRemaining())
    }

    func testMultipleBatches() {
        let batcher = TimeseriesBatcher(batchSize: 2)
        batcher.add(Sample(timestamp: 1, value: 10))
        batcher.add(Sample(timestamp: 2, value: 20))

        XCTAssertTrue(batcher.shouldFlush())
        let batch1 = batcher.flush()
        XCTAssertEqual(batch1.count, 2)

        batcher.add(Sample(timestamp: 3, value: 30))
        batcher.add(Sample(timestamp: 4, value: 40))

        XCTAssertTrue(batcher.shouldFlush())
        let batch2 = batcher.flush()
        XCTAssertEqual(batch2.count, 2)
        XCTAssertEqual(batch2[0].timestamp, 3)
    }
}
