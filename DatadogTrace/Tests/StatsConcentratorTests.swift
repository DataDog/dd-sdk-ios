/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class StatsConcentratorTests: XCTestCase {
    private let bucketDuration: Nanoseconds = 10_000_000_000 // 10s

    private func makeConcentrator(
        now: Nanoseconds = 100_000_000_000,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys
    ) -> StatsConcentrator {
        return StatsConcentrator(
            now: now,
            bucketDuration: bucketDuration,
            bufferLen: bufferLen,
            peerTagKeys: peerTagKeys
        )
    }

    // MARK: - Eligibility

    func testTopLevelSpanIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: nil, isTopLevel: true, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testMeasuredSpanIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: nil, isTopLevel: false, isMeasured: true)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testServerSpanKindIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "server", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testConsumerSpanKindIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "consumer", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testClientSpanKindIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "client", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testProducerSpanKindIsEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "producer", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testSpanKindIsCaseInsensitive() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "SERVER", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testInternalSpanKindIsNotEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: "internal", isTopLevel: false, isMeasured: false)
        XCTAssertFalse(StatsConcentrator.isEligible(snapshot))
    }

    func testNilSpanKindAndNotTopLevelOrMeasuredIsNotEligible() {
        let snapshot = SpanSnapshot.mockWith(spanKind: nil, isTopLevel: false, isMeasured: false)
        XCTAssertFalse(StatsConcentrator.isEligible(snapshot))
    }

    // MARK: - Aggregation

    func testIneligibleSpansAreDiscarded() {
        let concentrator = makeConcentrator(now: 0)
        let snapshot = SpanSnapshot.mockWith(
            startTime: 0,
            duration: 5_000_000_000,
            isTopLevel: false,
            isMeasured: false
        )

        concentrator.add(snapshot)
        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testSingleSpanProducesOneGroupInOneBucket() {
        let concentrator = makeConcentrator(now: 0)

        let snapshot = SpanSnapshot.mockWith(
            service: "web",
            operationName: "http.request",
            resource: "GET /api",
            startTime: 1_000_000_000,
            duration: 2_000_000_000,
            isTopLevel: true
        )

        concentrator.add(snapshot)
        let buckets = concentrator.flush(now: 100_000_000_000, force: true)

        XCTAssertEqual(buckets.count, 1)
        let bucket = buckets[0]
        XCTAssertEqual(bucket.stats.count, 1)

        let stats = bucket.stats[0]
        XCTAssertEqual(stats.service, "web")
        XCTAssertEqual(stats.name, "http.request")
        XCTAssertEqual(stats.resource, "GET /api")
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.errors, 0)
        XCTAssertEqual(stats.topLevelHits, 1)
    }

    func testMultipleSpansWithSameKeyAggregateIntoOneGroup() {
        let concentrator = makeConcentrator(now: 0)

        for i in 0..<5 {
            let snapshot = SpanSnapshot.mockWith(
                spanID: SpanID(rawValue: UInt64(i + 1)),
                service: "web",
                operationName: "http.request",
                resource: "GET /api",
                startTime: UInt64(i) * 1_000_000_000,
                duration: 500_000_000,
                isTopLevel: true
            )
            concentrator.add(snapshot)
        }

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)

        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.hits, 5)
        XCTAssertEqual(stats.topLevelHits, 5)
    }

    func testDifferentServicesProduceSeparateGroups() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            service: "web",
            operationName: "request",
            resource: "GET /",
            startTime: 1_000_000_000,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            service: "api",
            operationName: "request",
            resource: "GET /",
            startTime: 1_000_000_000,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].stats.count, 2)
    }

    func testErrorSpansIncrementErrorCount() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            isError: true,
            startTime: 1_000_000_000,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            isError: false,
            startTime: 1_000_000_000,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.hits, 2)
        XCTAssertEqual(stats.errors, 1)
    }

    func testDurationIsAccumulatedAcrossSpans() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 3_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            startTime: 0,
            duration: 7_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.duration, 10_000_000_000)
    }

    func testNonTopLevelSpanDoesNotIncrementTopLevelHits() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            parentSpanID: SpanID(rawValue: 99),
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.topLevelHits, 0)
    }

    // MARK: - Time Bucketing

    func testSpansAreAssignedToBucketByEndTime() {
        let concentrator = makeConcentrator(now: 0)

        // End time = 5s (bucket 0s)
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            startTime: 0,
            duration: 5_000_000_000,
            isTopLevel: true
        ))
        // End time = 15s (bucket 10s)
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            startTime: 5_000_000_000,
            duration: 10_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 2)

        let sortedBuckets = buckets.sorted { $0.start < $1.start }
        XCTAssertEqual(sortedBuckets[0].start, 0)
        XCTAssertEqual(sortedBuckets[1].start, 10_000_000_000)
    }

    func testBucketAlignment() {
        XCTAssertEqual(
            StatsConcentrator.alignTimestamp(15_500_000_000, bucketDuration: 10_000_000_000),
            10_000_000_000
        )
        XCTAssertEqual(
            StatsConcentrator.alignTimestamp(10_000_000_000, bucketDuration: 10_000_000_000),
            10_000_000_000
        )
        XCTAssertEqual(
            StatsConcentrator.alignTimestamp(9_999_999_999, bucketDuration: 10_000_000_000),
            0
        )
    }

    // MARK: - Flushing

    func testFlushOnlyReturnsCompletedBuckets() {
        let concentrator = makeConcentrator(now: 0)

        // Span ending at 5s goes into bucket 0s
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            startTime: 0,
            duration: 5_000_000_000,
            isTopLevel: true
        ))

        // Span ending at 25s goes into bucket 20s
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            startTime: 20_000_000_000,
            duration: 5_000_000_000,
            isTopLevel: true
        ))

        // At t=15s, cutoff = 15 - 20 = -5 (negative). No buckets are old enough.
        let earlyBuckets = concentrator.flush(now: 15_000_000_000, force: false)
        XCTAssertEqual(earlyBuckets.count, 0)

        // At t=25s, cutoff = 25 - 20 = 5. Bucket 0s (ts=0 <= 5) is flushed.
        // Bucket 20s (ts=20 > 5) stays.
        let midBuckets = concentrator.flush(now: 25_000_000_000, force: false)
        XCTAssertEqual(midBuckets.count, 1)
        XCTAssertEqual(midBuckets[0].start, 0)

        // At t=45s, cutoff = 45 - 20 = 25. Bucket 20s (ts=20 <= 25) is flushed.
        let lateBuckets = concentrator.flush(now: 45_000_000_000, force: false)
        XCTAssertEqual(lateBuckets.count, 1)
        XCTAssertEqual(lateBuckets[0].start, 20_000_000_000)
    }

    func testForceFlushReturnsAllBuckets() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            startTime: 90_000_000_000,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 91_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 2)
    }

    func testFlushRemovesBucketsFromConcentrator() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let first = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(first.count, 1)

        let second = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(second.isEmpty)
    }

    func testFlushWithNoSpansReturnsEmpty() {
        let concentrator = makeConcentrator(now: 0)
        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty)
    }

    // MARK: - Oldest Timestamp

    func testSpansOlderThanOldestTsGoToOldestBucket() {
        let now: Nanoseconds = 50_000_000_000
        let concentrator = makeConcentrator(now: now)

        // Flush to advance oldestTs
        _ = concentrator.flush(now: 80_000_000_000, force: false)

        // Add a span with end time well in the past
        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 200_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
    }

    // MARK: - Aggregation Key

    func testDifferentResourcesProduceSeparateGroups() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            resource: "GET /users",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            resource: "POST /users",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].stats.count, 2)
    }

    func testDifferentHTTPStatusCodesProduceSeparateGroups() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            httpStatusCode: 200,
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            httpStatusCode: 404,
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].stats.count, 2)
    }

    func testIsTraceRootDerivedFromParentSpanID() {
        let concentrator = makeConcentrator(now: 0)

        // Root span (no parent)
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 1),
            parentSpanID: nil,
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))
        // Child span (has parent)
        concentrator.add(SpanSnapshot.mockWith(
            spanID: SpanID(rawValue: 2),
            parentSpanID: SpanID(rawValue: 1),
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].stats.count, 2)

        let root = buckets[0].stats.first { $0.isTraceRoot == .true }
        let child = buckets[0].stats.first { $0.isTraceRoot == .false }
        XCTAssertNotNil(root)
        XCTAssertNotNil(child)
    }

    // MARK: - Peer Tags

    func testPeerTagsIncludedForClientSpanKind() {
        let concentrator = makeConcentrator(now: 0, peerTagKeys: ["peer.service", "out.host"])

        concentrator.add(SpanSnapshot.mockWith(
            spanKind: "client",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: false,
            peerTags: ["peer.service": "downstream-svc", "out.host": "db.example.com"]
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.peerTags.count, 2)
        XCTAssertTrue(stats.peerTags.contains("peer.service:downstream-svc"))
        XCTAssertTrue(stats.peerTags.contains("out.host:db.example.com"))
    }

    func testPeerTagsNotIncludedForServerSpanKind() {
        let concentrator = makeConcentrator(now: 0, peerTagKeys: ["peer.service"])

        concentrator.add(SpanSnapshot.mockWith(
            spanKind: "server",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: false,
            peerTags: ["peer.service": "downstream-svc"]
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertTrue(stats.peerTags.isEmpty)
    }

    func testPeerTagsIncludedForProducerSpanKind() {
        let concentrator = makeConcentrator(now: 0, peerTagKeys: ["peer.service"])

        concentrator.add(SpanSnapshot.mockWith(
            spanKind: "producer",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: false,
            peerTags: ["peer.service": "msg-queue"]
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertTrue(stats.peerTags.contains("peer.service:msg-queue"))
    }

    // MARK: - FNV-64a Hash

    func testFNV64aEmptyReturnsZero() {
        XCTAssertEqual(StatsUtils.fnv64a([]), 0)
    }

    func testFNV64aDeterministic() {
        let tags = ["peer.service:web", "out.host:db.local"]
        let hash1 = StatsUtils.fnv64a(tags)
        let hash2 = StatsUtils.fnv64a(tags)
        XCTAssertEqual(hash1, hash2)
    }

    func testFNV64aSortsTags() {
        let hash1 = StatsUtils.fnv64a(["b:2", "a:1"])
        let hash2 = StatsUtils.fnv64a(["a:1", "b:2"])
        XCTAssertEqual(hash1, hash2)
    }

    func testFNV64aDifferentTagsProduceDifferentHash() {
        let hash1 = StatsUtils.fnv64a(["a:1"])
        let hash2 = StatsUtils.fnv64a(["b:2"])
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Stochastic Rounding

    func testStochasticRoundIntegerValues() {
        XCTAssertEqual(StatsUtils.stochasticRound(5.0), 5)
        XCTAssertEqual(StatsUtils.stochasticRound(0.0), 0)
        XCTAssertEqual(StatsUtils.stochasticRound(100.0), 100)
    }

    // MARK: - Exported Bucket Structure

    func testExportedBucketContainsBucketDuration() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].duration, bucketDuration)
    }

    func testExportedGroupedStatsHasEmptySketchPlaceholders() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = buckets[0].stats[0]
        XCTAssertEqual(stats.okSummary, Data())
        XCTAssertEqual(stats.errorSummary, Data())
    }

    // MARK: - Thread Safety

    func testConcurrentAddAndFlush() {
        let concentrator = makeConcentrator(now: 0)
        let iterations = 1_000
        let expectation = XCTestExpectation(description: "concurrent operations")
        expectation.expectedFulfillmentCount = iterations + 1

        for i in 0..<iterations {
            DispatchQueue.global().async {
                concentrator.add(SpanSnapshot.mockWith(
                    spanID: SpanID(rawValue: UInt64(i + 1)),
                    startTime: UInt64(i) * 1_000_000,
                    duration: 500_000,
                    isTopLevel: true
                ))
                expectation.fulfill()
            }
        }

        DispatchQueue.global().async {
            _ = concentrator.flush(now: 100_000_000_000, force: true)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }

    // MARK: - Service Source Passthrough

    func testServiceSourceIncludedInExportedStats() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true,
            serviceSource: "m"
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].stats[0].serviceSource, "m")
    }

    // MARK: - Synthetics

    func testSyntheticsAlwaysFalseForMobile() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertFalse(buckets[0].stats[0].synthetics)
    }

    // MARK: - Span Type Passthrough

    func testSpanTypeIncludedInExportedStats() {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            type: "http",
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets[0].stats[0].type, "http")
    }
}
