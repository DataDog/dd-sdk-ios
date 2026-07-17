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
        initialConsent: TrackingConsent = .granted,
        bufferLen: Int = StatsConcentrator.defaultBufferLen,
        peerTagKeys: [String] = StatsConcentrator.defaultPeerTagKeys
    ) -> StatsConcentrator {
        return StatsConcentrator(
            now: now,
            initialConsent: initialConsent,
            bucketDuration: bucketDuration,
            bufferLen: bufferLen,
            peerTagKeys: peerTagKeys
        )
    }

    private func makeEligibleSnapshot(now: Nanoseconds = 0) -> SpanSnapshot {
        return SpanSnapshot.mockWith(
            service: "web",
            operationName: "http.request",
            resource: "GET /api",
            startTime: now,
            duration: 2_000_000_000,
            isTopLevel: true
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

    func testSingleSpanProducesOneGroupInOneBucket() throws {
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
        let bucket = try XCTUnwrap(buckets.first)
        XCTAssertEqual(bucket.stats.count, 1)

        let stats = try XCTUnwrap(bucket.stats.first)
        XCTAssertEqual(stats.service, "web")
        XCTAssertEqual(stats.name, "http.request")
        XCTAssertEqual(stats.resource, "GET /api")
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.errors, 0)
        XCTAssertEqual(stats.topLevelHits, 1)
    }

    func testMultipleSpansWithSameKeyAggregateIntoOneGroup() throws {
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

        let stats = try XCTUnwrap(buckets.first?.stats.first)
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
        XCTAssertEqual(buckets.first?.stats.count, 2)
    }

    func testErrorSpansIncrementErrorCount() throws {
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
        let stats = try XCTUnwrap(buckets.first?.stats.first)
        XCTAssertEqual(stats.hits, 2)
        XCTAssertEqual(stats.errors, 1)
    }

    func testDurationIsAccumulatedAcrossSpans() throws {
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
        let stats = try XCTUnwrap(buckets.first?.stats.first)
        XCTAssertEqual(stats.duration, 10_000_000_000)
    }

    func testNonTopLevelSpanDoesNotIncrementTopLevelHits() throws {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            parentSpanID: SpanID(rawValue: 99),
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = try XCTUnwrap(buckets.first?.stats.first)
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
        XCTAssertEqual(sortedBuckets.first?.start, 0)
        XCTAssertEqual(sortedBuckets.last?.start, 10_000_000_000)
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
        XCTAssertEqual(midBuckets.first?.start, 0)

        // At t=45s, cutoff = 45 - 20 = 25. Bucket 20s (ts=20 <= 25) is flushed.
        let lateBuckets = concentrator.flush(now: 45_000_000_000, force: false)
        XCTAssertEqual(lateBuckets.count, 1)
        XCTAssertEqual(lateBuckets.first?.start, 20_000_000_000)
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
        XCTAssertEqual(buckets.first?.stats.count, 2)
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
        XCTAssertEqual(buckets.first?.stats.count, 2)
    }

    func testIsTraceRootDerivedFromParentSpanID() throws {
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
        let stats = try XCTUnwrap(buckets.first).stats
        XCTAssertEqual(stats.count, 2)

        let root = stats.first { $0.isTraceRoot == .true }
        let child = stats.first { $0.isTraceRoot == .false }
        XCTAssertNotNil(root)
        XCTAssertNotNil(child)
    }

    // MARK: - Peer Tags

    func testPeerTagsIncludedForClientSpanKind() throws {
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
        let stats = try XCTUnwrap(buckets.first?.stats.first)
        XCTAssertEqual(stats.peerTags.count, 2)
        XCTAssertTrue(stats.peerTags.contains("peer.service:downstream-svc"))
        XCTAssertTrue(stats.peerTags.contains("out.host:db.example.com"))
    }

    func testPeerTagsNotIncludedForServerSpanKind() throws {
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
        let stats = try XCTUnwrap(buckets.first?.stats.first)
        XCTAssertTrue(stats.peerTags.isEmpty)
    }

    func testPeerTagsIncludedForProducerSpanKind() throws {
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
        let stats = try XCTUnwrap(buckets.first?.stats.first)
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
        XCTAssertEqual(buckets.first?.duration, bucketDuration)
    }

    // MARK: - Latency Sketches

    func testOkSpanPopulatesOkSummaryNotErrorSummary() throws {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            isError: false,
            startTime: 0,
            duration: 1_000_000_000, // 1s
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = try XCTUnwrap(buckets.first?.stats.first)

        // An empty DDSketch encodes only the mapping field (11 bytes); a sketch
        // that has recorded at least one value also encodes a positive store.
        // The ok summary must therefore be longer than the empty (mapping-only)
        // baseline, and the error summary must be exactly the baseline.
        let emptySketchBytes = DDSketch.makeForStats().toProtoBytes()
        XCTAssertGreaterThan(stats.okSummary.count, emptySketchBytes.count)
        XCTAssertEqual(stats.errorSummary, emptySketchBytes)
    }

    func testErrorSpanPopulatesErrorSummaryNotOkSummary() throws {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            isError: true,
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = try XCTUnwrap(buckets.first?.stats.first)

        let emptySketchBytes = DDSketch.makeForStats().toProtoBytes()
        XCTAssertEqual(stats.okSummary, emptySketchBytes)
        XCTAssertGreaterThan(stats.errorSummary.count, emptySketchBytes.count)
    }

    func testMixedOkAndErrorSpans_populateBothSummaries() throws {
        let concentrator = makeConcentrator(now: 0)

        // Two ok spans + one error span, all into the same aggregation group.
        for _ in 0..<2 {
            concentrator.add(SpanSnapshot.mockWith(
                isError: false,
                startTime: 0,
                duration: 500_000_000, // 0.5s
                isTopLevel: true
            ))
        }
        concentrator.add(SpanSnapshot.mockWith(
            isError: true,
            startTime: 0,
            duration: 2_000_000_000, // 2s
            isTopLevel: true
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
        let stats = try XCTUnwrap(buckets.first?.stats.first)

        XCTAssertEqual(stats.hits, 3)
        XCTAssertEqual(stats.errors, 1)

        // Both sketches contain values now, so both must exceed the empty baseline.
        let emptySketchBytes = DDSketch.makeForStats().toProtoBytes()
        XCTAssertGreaterThan(stats.okSummary.count, emptySketchBytes.count)
        XCTAssertGreaterThan(stats.errorSummary.count, emptySketchBytes.count)
    }

    func testIneligibleSpansDoNotContributeToSummaries() {
        let concentrator = makeConcentrator(now: 0)

        // Ineligible (not top-level, not measured, no qualifying span_kind).
        concentrator.add(SpanSnapshot.mockWith(
            isError: false,
            startTime: 0,
            duration: 1_000_000_000,
            isTopLevel: false,
            isMeasured: false
        ))

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty, "ineligible spans must not produce any group")
    }

    /// Fixture-style cross-check: the bytes emitted for a populated `okSummary` are
    /// exactly what a `DDSketch` built independently from the same input produces.
    /// Catches any future regression where the wiring stops feeding the sketch the
    /// raw `Double(duration)` we expect.
    func testOkSummaryBytesMatchIndependentlyBuiltSketch() throws {
        let concentrator = makeConcentrator(now: 0)
        let durations: [Nanoseconds] = [100_000_000, 250_000_000, 1_000_000_000, 2_500_000_000]

        for duration in durations {
            concentrator.add(SpanSnapshot.mockWith(
                isError: false,
                startTime: 0,
                duration: duration,
                isTopLevel: true
            ))
        }

        var reference = DDSketch.makeForStats()
        for duration in durations {
            reference.add(Double(duration))
        }

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        let stats = try XCTUnwrap(buckets.first?.stats.first)
        XCTAssertEqual(stats.okSummary, reference.toProtoBytes())
    }

    /// Two spans with different resources land in two distinct aggregation groups.
    /// Each group's sketch must reflect only its own span's duration, not the other's.
    func testDistinctAggregationKeysGetIndependentSketches() throws {
        let concentrator = makeConcentrator(now: 0)

        concentrator.add(SpanSnapshot.mockWith(
            resource: "GET /a",
            isError: false,
            startTime: 0,
            duration: 100_000_000,
            isTopLevel: true
        ))
        concentrator.add(SpanSnapshot.mockWith(
            resource: "GET /b",
            isError: false,
            startTime: 0,
            duration: 2_000_000_000,
            isTopLevel: true
        ))

        var sketchA = DDSketch.makeForStats()
        sketchA.add(100_000_000)
        var sketchB = DDSketch.makeForStats()
        sketchB.add(2_000_000_000)

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
        let allStats = try XCTUnwrap(buckets.first).stats
        XCTAssertEqual(allStats.count, 2)

        let statsByResource = Dictionary(uniqueKeysWithValues: allStats.map { ($0.resource, $0) })
        XCTAssertEqual(statsByResource["GET /a"]?.okSummary, sketchA.toProtoBytes())
        XCTAssertEqual(statsByResource["GET /b"]?.okSummary, sketchB.toProtoBytes())
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
        XCTAssertEqual(buckets.first?.stats.first?.serviceSource, "m")
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
        XCTAssertEqual(buckets.first?.stats.first?.synthetics, false)
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
        XCTAssertEqual(buckets.first?.stats.first?.type, "http")
    }

    // MARK: - Consent

    func testWhenInitialConsentIsNotGranted_itDropsAllSpans() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .notGranted)

        concentrator.add(makeEligibleSnapshot())

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testWhenInitialConsentIsPending_itAggregatesSpans() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .pending)

        concentrator.add(makeEligibleSnapshot())

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
    }

    func testWhenConsentIsRevoked_itDiscardsBufferedData() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .granted)
        concentrator.add(makeEligibleSnapshot())

        // Revoke, then re-grant: the buffered span must stay dropped, proving the buffer was
        // discarded on revocation rather than merely gated while not granted.
        concentrator.updateConsent(.notGranted)
        concentrator.updateConsent(.granted)

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testWhenConsentRevoked_itDropsSpansRecordedAfterRevocation() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .granted)

        concentrator.updateConsent(.notGranted)
        concentrator.add(makeEligibleSnapshot())

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testWhenConsentMovesBetweenGrantedAndPending_itKeepsAggregating() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .granted)
        concentrator.add(makeEligibleSnapshot())

        // Both are recording states, so neither transition should drop the buffered span.
        concentrator.updateConsent(.pending)
        concentrator.updateConsent(.granted)

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.stats.first?.hits, 1)
    }

    func testWhenConsentIsGrantedAfterNotGranted_itResumesAggregating() {
        let concentrator = makeConcentrator(now: 0, initialConsent: .notGranted)

        concentrator.updateConsent(.granted)
        concentrator.add(makeEligibleSnapshot())

        let buckets = concentrator.flush(now: 100_000_000_000, force: true)
        XCTAssertEqual(buckets.count, 1)
    }
}
