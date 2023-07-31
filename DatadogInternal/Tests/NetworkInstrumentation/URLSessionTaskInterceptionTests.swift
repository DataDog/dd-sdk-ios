/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class URLSessionTaskInterceptionTests: XCTestCase {
    func testWhenInterceptionIsCreated_itHasUniqueIdentifier() {
        // When
        let interception1 = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true)
        let interception2 = URLSessionTaskInterception(request: .mockAny(), isFirstParty: false)

        // Then
        XCTAssertNotEqual(interception1.identifier, interception2.identifier)
    }

    func testWhenInterceptionReceivesData_itAppendsItToPreviousData() {
        let chunk1 = "abc".utf8Data
        let chunk2 = "def".utf8Data
        let chunk3 = "ghi".utf8Data

        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        XCTAssertNil(interception.data)

        // When
        interception.register(nextData: chunk1)
        let data1 = interception.data

        interception.register(nextData: chunk2)
        let data2 = interception.data

        interception.register(nextData: chunk3)
        let data3 = interception.data

        // Then
        XCTAssertEqual(data1, chunk1)
        XCTAssertEqual(data2, chunk1 + chunk2)
        XCTAssertEqual(data3, chunk1 + chunk2 + chunk3)
    }

    func testWhenInterceptionReceivesBothMetricsAndCompletion_itIsConsideredDone() {
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .mockAny())

        // When
        interception.register(response: .mockAny(), error: nil)
        XCTAssertFalse(interception.isDone)
        interception.register(metrics: .mockAny())

        // Then
        XCTAssertTrue(interception.isDone)
    }
}

class ResourceMetricsTests: XCTestCase {
    func testCalculatingMetricDuration() {
        let date = Date()
        let metric = ResourceMetrics.DateInterval(start: date, end: date.addingTimeInterval(2))
        XCTAssertEqual(metric.duration, 2)
    }

    func testWhenTaskMakesSingleFetchFromNetwork_thenAllMetricsExceptRedirectionAreCollected() {
        guard #available(iOS 13, tvOS 13, *) else {
            return
        }

        let taskInterval = DateInterval(
            start: .mockDecember15th2019At10AMUTC(),
            end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 5)
        )
        let taskTransaction: URLSessionTaskTransactionMetrics = .mockBySpreadingDetailsBetween(
            start: taskInterval.start,
            end: taskInterval.end,
            resourceFetchType: .networkLoad
        )

        // When
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            taskInterval: taskInterval,
            transactionMetrics: [taskTransaction]
        )

        // Then
        let resourceMetrics = ResourceMetrics(taskMetrics: taskMetrics)
        XCTAssertEqual(resourceMetrics.fetch.start, taskInterval.start)
        XCTAssertEqual(resourceMetrics.fetch.end, taskInterval.end)
        XCTAssertNil(resourceMetrics.redirection, "Single-transaction task should not have redirection phase.")
        XCTAssertEqual(resourceMetrics.dns?.start, taskTransaction.domainLookupStartDate!)
        XCTAssertEqual(resourceMetrics.dns?.end, taskTransaction.domainLookupEndDate!)
        XCTAssertEqual(resourceMetrics.connect?.start, taskTransaction.connectStartDate!)
        XCTAssertEqual(resourceMetrics.connect?.end, taskTransaction.connectEndDate!)
        XCTAssertEqual(resourceMetrics.ssl?.start, taskTransaction.secureConnectionStartDate!)
        XCTAssertEqual(resourceMetrics.ssl?.end, taskTransaction.secureConnectionEndDate!)
        XCTAssertEqual(resourceMetrics.firstByte?.start, taskTransaction.requestStartDate!)
        XCTAssertEqual(resourceMetrics.firstByte?.end, taskTransaction.responseStartDate!)
        XCTAssertEqual(resourceMetrics.download?.start, taskTransaction.responseStartDate!)
        XCTAssertEqual(resourceMetrics.download?.end, taskTransaction.responseEndDate!)
        XCTAssertEqual(resourceMetrics.responseSize, taskTransaction.countOfResponseBodyBytesAfterDecoding)
    }

    func testWhenTaskMakesMultipleFetchesFromNetwork_thenAllMetricsAreCollected() {
        guard #available(iOS 13, tvOS 13, *) else {
            return
        }

        let taskInterval = DateInterval(
            start: .mockDecember15th2019At10AMUTC(),
            end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 10)
        )
        // Transaction 1 spreads from 0% to 30% of the overall task duration.
        let transaction1: URLSessionTaskTransactionMetrics = .mockBySpreadingDetailsBetween(
            start: taskInterval.start,
            end: taskInterval.start.addingTimeInterval(taskInterval.duration * 0.30),
            resourceFetchType: .networkLoad
        )
        // Transaction 2 spreads from 35% to 60% of the overall task duration.
        let transaction2: URLSessionTaskTransactionMetrics = .mockBySpreadingDetailsBetween(
            start: taskInterval.start.addingTimeInterval(taskInterval.duration * 0.35),
            end: taskInterval.start.addingTimeInterval(taskInterval.duration * 0.60),
            resourceFetchType: .networkLoad
        )
        // Transaction 3 spreads from 65% to 100% of the overall task duration.
        let transaction3: URLSessionTaskTransactionMetrics = .mockBySpreadingDetailsBetween(
            start: taskInterval.start.addingTimeInterval(taskInterval.duration * 0.65),
            end: taskInterval.start.addingTimeInterval(taskInterval.duration),
            resourceFetchType: .networkLoad
        )

        // When
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            taskInterval: taskInterval,
            transactionMetrics: [transaction1, transaction2, transaction3]
        )

        // Then
        let resourceMetrics = ResourceMetrics(taskMetrics: taskMetrics)
        XCTAssertEqual(resourceMetrics.fetch.start, taskInterval.start)
        XCTAssertEqual(resourceMetrics.fetch.end, taskInterval.end)
        XCTAssertEqual(
            resourceMetrics.redirection?.start,
            transaction1.fetchStartDate!,
            "Redirection should start with from 1st transaction"
        )
        XCTAssertEqual(
            resourceMetrics.redirection?.end,
            transaction2.responseEndDate!,
            "Redirection should end with from 2nd transaction"
        )
        XCTAssertEqual(resourceMetrics.dns?.start, transaction3.domainLookupStartDate!)
        XCTAssertEqual(resourceMetrics.dns?.end, transaction3.domainLookupEndDate!)
        XCTAssertEqual(resourceMetrics.connect?.start, transaction3.connectStartDate!)
        XCTAssertEqual(resourceMetrics.connect?.end, transaction3.connectEndDate!)
        XCTAssertEqual(resourceMetrics.ssl?.start, transaction3.secureConnectionStartDate!)
        XCTAssertEqual(resourceMetrics.ssl?.end, transaction3.secureConnectionEndDate!)
        XCTAssertEqual(resourceMetrics.firstByte?.start, transaction3.requestStartDate!)
        XCTAssertEqual(resourceMetrics.firstByte?.end, transaction3.responseStartDate!)
        XCTAssertEqual(resourceMetrics.download?.start, transaction3.responseStartDate!)
        XCTAssertEqual(resourceMetrics.download?.end, transaction3.responseEndDate!)
        XCTAssertEqual(resourceMetrics.responseSize, transaction3.countOfResponseBodyBytesAfterDecoding)
    }

    func testWhenTaskMakesFetchFromLocalCache_thenOnlyFetchMetricIsCollected() {
        guard #available(iOS 13, tvOS 13, *) else {
            return
        }

        let taskInterval = DateInterval(
            start: .mockDecember15th2019At10AMUTC(),
            end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 5)
        )
        let taskTransaction: URLSessionTaskTransactionMetrics = .mockBySpreadingDetailsBetween(
            start: taskInterval.start,
            end: taskInterval.end,
            resourceFetchType: .localCache
        )

        // When
        let taskMetrics: URLSessionTaskMetrics = .mockWith(
            taskInterval: taskInterval,
            transactionMetrics: [taskTransaction]
        )

        // Then
        let resourceMetrics = ResourceMetrics(taskMetrics: taskMetrics)
        XCTAssertEqual(resourceMetrics.fetch.start, taskInterval.start)
        XCTAssertEqual(resourceMetrics.fetch.end, taskInterval.end)
        XCTAssertNil(
            resourceMetrics.redirection,
            "`redirection` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.dns,
            "`dns` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.connect,
            "`connect` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.ssl,
            "`ssl` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.firstByte,
            "`firstByte` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.download,
            "`download` should not be tracked for cache transactions."
        )
        XCTAssertNil(
            resourceMetrics.responseSize,
            "`responseSize` should not be tracked for cache transactions."
        )
    }
}
