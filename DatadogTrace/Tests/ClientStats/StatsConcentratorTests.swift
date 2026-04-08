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
    // MARK: - Eligibility

    func testIsEligible_whenTopLevel() {
        let snapshot = SpanSnapshot.mock(spanKind: nil, isTopLevel: true, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsEligible_whenMeasured() {
        let snapshot = SpanSnapshot.mock(spanKind: nil, isTopLevel: false, isMeasured: true)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsEligible_whenSpanKindIsServer() {
        let snapshot = SpanSnapshot.mock(spanKind: "server", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsEligible_whenSpanKindIsClient() {
        let snapshot = SpanSnapshot.mock(spanKind: "client", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsEligible_whenSpanKindIsConsumer() {
        let snapshot = SpanSnapshot.mock(spanKind: "consumer", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsEligible_whenSpanKindIsProducer() {
        let snapshot = SpanSnapshot.mock(spanKind: "producer", isTopLevel: false, isMeasured: false)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
    }

    func testIsNotEligible_whenNotTopLevelNotMeasuredInternalKind() {
        let snapshot = SpanSnapshot.mock(spanKind: "internal", isTopLevel: false, isMeasured: false)
        XCTAssertFalse(StatsConcentrator.isEligible(snapshot))
    }

    func testIsNotEligible_whenNotTopLevelNotMeasuredNoKind() {
        let snapshot = SpanSnapshot.mock(spanKind: nil, isTopLevel: false, isMeasured: false)
        XCTAssertFalse(StatsConcentrator.isEligible(snapshot))
    }

    // MARK: - Aggregation

    func testAdd_aggregatesHitsForEligibleSpans() {
        let concentrator = StatsConcentrator(bucketDuration: 10_000_000_000)
        let snapshot = SpanSnapshot.mock(
            operationName: "http.request",
            startTime: 1_000_000_000,
            duration: 500_000_000,
            isTopLevel: true
        )

        concentrator.add(snapshot)
        concentrator.add(snapshot)

        // Wait for async aggregation
        let expectation = expectation(description: "aggregation completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        let buckets = concentrator.flush(olderThan: UInt64.max)
        XCTAssertEqual(buckets.count, 1)

        let bucket = buckets[0]
        let groupValues = Array(bucket.groups.values)
        XCTAssertEqual(groupValues.count, 1)
        XCTAssertEqual(groupValues[0].hits, 2)
        XCTAssertEqual(groupValues[0].duration, 1_000_000_000)
    }

    func testAdd_countsErrors() {
        let concentrator = StatsConcentrator(bucketDuration: 10_000_000_000)
        let errorSnapshot = SpanSnapshot.mock(isError: true, isTopLevel: true)
        let okSnapshot = SpanSnapshot.mock(isError: false, isTopLevel: true)

        concentrator.add(errorSnapshot)
        concentrator.add(okSnapshot)

        let expectation = expectation(description: "aggregation completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        let buckets = concentrator.flush(olderThan: UInt64.max)
        let group = buckets.flatMap { Array($0.groups.values) }.first!
        XCTAssertEqual(group.hits, 2)
        XCTAssertEqual(group.errors, 1)
    }

    func testAdd_doesNotAggregateIneligibleSpans() {
        let concentrator = StatsConcentrator(bucketDuration: 10_000_000_000)
        let ineligible = SpanSnapshot.mock(spanKind: nil, isTopLevel: false, isMeasured: false)

        concentrator.add(ineligible)

        let expectation = expectation(description: "aggregation completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        let buckets = concentrator.flush(olderThan: UInt64.max)
        XCTAssertTrue(buckets.isEmpty)
    }

    // MARK: - Flushing

    func testFlush_onlyReturnsBucketsOlderThanCutoff() {
        let bucketDuration: UInt64 = 10_000_000_000
        let concentrator = StatsConcentrator(bucketDuration: bucketDuration)

        let earlySpan = SpanSnapshot.mock(startTime: 5_000_000_000, duration: 1_000_000_000, isTopLevel: true)
        let lateSpan = SpanSnapshot.mock(startTime: 50_000_000_000, duration: 1_000_000_000, isTopLevel: true)

        concentrator.add(earlySpan)
        concentrator.add(lateSpan)

        let expectation = expectation(description: "aggregation completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        // Only flush buckets older than 20s mark
        let flushed = concentrator.flush(olderThan: 20_000_000_000)
        XCTAssertEqual(flushed.count, 1)

        // The late span bucket should still be there
        let remaining = concentrator.flush(olderThan: UInt64.max)
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - Aggregation Key

    func testAggregationKey_differsByService() {
        let concentrator = StatsConcentrator(bucketDuration: 10_000_000_000)
        let s1 = SpanSnapshot.mock(service: "service-a", isTopLevel: true)
        let s2 = SpanSnapshot.mock(service: "service-b", isTopLevel: true)

        concentrator.add(s1)
        concentrator.add(s2)

        let expectation = expectation(description: "aggregation completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        let buckets = concentrator.flush(olderThan: UInt64.max)
        let totalGroups = buckets.reduce(0) { $0 + $1.groups.count }
        XCTAssertEqual(totalGroups, 2)
    }
}

// MARK: - SpanSnapshot Test Helpers

extension SpanSnapshot {
    static func mock(
        traceID: TraceID = .mockAny(),
        spanID: SpanID = .mockAny(),
        parentSpanID: SpanID? = nil,
        service: String = "test-service",
        operationName: String = "test.operation",
        resource: String = "test-resource",
        type: String = "custom",
        spanKind: String? = nil,
        httpStatusCode: UInt32 = 0,
        isError: Bool = false,
        startTime: UInt64 = 1_000_000_000,
        duration: UInt64 = 100_000_000,
        isTopLevel: Bool = true,
        isMeasured: Bool = false,
        peerTags: [String: String] = [:],
        isSynthetics: Bool = false,
        serviceSource: String? = nil
    ) -> SpanSnapshot {
        SpanSnapshot(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            service: service,
            operationName: operationName,
            resource: resource,
            type: type,
            spanKind: spanKind,
            httpStatusCode: httpStatusCode,
            isError: isError,
            startTime: startTime,
            duration: duration,
            isTopLevel: isTopLevel,
            isMeasured: isMeasured,
            peerTags: peerTags,
            isSynthetics: isSynthetics,
            serviceSource: serviceSource
        )
    }
}
