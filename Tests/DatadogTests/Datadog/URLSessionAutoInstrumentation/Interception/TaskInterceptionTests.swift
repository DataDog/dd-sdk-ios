/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TaskInterceptionTests: XCTestCase {
    func testWhenInterceptionIsCreated_itHasUniqueIdentifier() {
        // When
        let interception1 = TaskInterception(request: .mockAny())
        let interception2 = TaskInterception(request: .mockAny())

        // Then
        XCTAssertNotEqual(interception1.identifier, interception2.identifier)
    }

    func testWhenInterceptionReceivesBothMetricsAndCompletion_itIsConsideredDone() {
        let interception = TaskInterception(request: .mockAny())

        // When
        interception.register(completion: .mockAny())
        XCTAssertFalse(interception.isDone)
        interception.register(metrics: .mockAny())

        // Then
        XCTAssertTrue(interception.isDone)
    }
}

class ResourceMetricsTests: XCTestCase {
    // MARK: - `fetch` metric

    func testGivenTaskMetricsWithTransactions_whenComputingResourceFetchMetric_itUsesLastTransactionValues() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            transactionMetrics: [
                .mockAny(),
                .mockAny(),
                .mockWith(
                    fetchStartDate: .mockDecember15th2019At10AMUTC(),
                    responseEndDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            ]
        )

        // When
        let resourceFetch = ResourceMetrics(taskMetrics: taskMetrics).fetch

        // Then
        XCTAssertEqual(resourceFetch.start, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceFetch.end, .mockDecember15th2019At10AMUTC(addingTimeInterval: 2))
    }

    func testGivenTaskMetricsWithNoTransactions_whenComputingResourceFetchMetric_itDefaultsToTaskValues() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            taskInterval: .init(
                start: .mockDecember15th2019At10AMUTC(),
                end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
            ),
            transactionMetrics: []
        )

        // When
        let resourceFetch = ResourceMetrics(taskMetrics: taskMetrics).fetch

        // Then
        XCTAssertEqual(resourceFetch.start, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceFetch.end, .mockDecember15th2019At10AMUTC(addingTimeInterval: 2))
    }

    // MARK: - `dns` metric

    func testGivenTaskMetricsWithTransactions_whenComputingResourceDNSMetric_itUsesLastTransactionValues() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            transactionMetrics: [
                .mockAny(),
                .mockAny(),
                .mockWith(
                    domainLookupStartDate: .mockDecember15th2019At10AMUTC(),
                    domainLookupEndDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            ]
        )

        // When
        let resourceDNS = ResourceMetrics(taskMetrics: taskMetrics).dns

        // Then
        XCTAssertEqual(resourceDNS?.start, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceDNS?.duration, 2)
    }

    func testGivenTaskMetricsWithNoTransactions_whenComputingResourceDNSMetric_itNotAvailable() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            transactionMetrics: []
        )

        // When
        let resourceDNS = ResourceMetrics(taskMetrics: taskMetrics).dns

        // Then
        XCTAssertNil(resourceDNS)
    }

    // MARK: - `responseSize` metric

    func testGivenTaskMetricsWithTransactions_whenComputingResourceResponseSizeMetric_itUsesLastTransactionValues() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            transactionMetrics: [
                .mockAny(),
                .mockAny(),
                .mockWith(
                    countOfResponseBodyBytesAfterDecoding: 1_024
                )
            ]
        )

        // When
        let resourceResponseSize = ResourceMetrics(taskMetrics: taskMetrics).responseSize

        // Then
        XCTAssertEqual(resourceResponseSize, 1_024)
    }

    func testGivenTaskMetricsWithNoTransactions_whenComputingResourceResponseSizeMetric_itNotAvailable() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            transactionMetrics: []
        )

        // When
        let resourceResponseSize = ResourceMetrics(taskMetrics: taskMetrics).responseSize

        // Then
        XCTAssertNil(resourceResponseSize)
    }
}
