/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogFlags

final class FlagAssignmentsRequestOperationTests: XCTestCase {
    func testPreservesRequestAcrossRetry() {
        // Given
        let scheduler = ManualScheduler()
        var request = URLRequest(url: .mockAny())
        request.setValue("custom-value", forHTTPHeaderField: "X-Custom-Header")
        request.httpBody = Data("request-body".utf8)
        var capturedRequests: [URLRequest] = []
        let operation = makeOperation(
            retryCount: 1,
            fetch: { request, completion in
                capturedRequests.append(request)
                completion(.success(Self.response(statusCode: capturedRequests.count == 1 ? 500 : 200)))
                return {}
            },
            request: request,
            schedule: scheduler.schedule,
            jitter: { _ in 0 }
        )
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

        // When
        operation.start { capturedResult = $0 }
        scheduler.runNext()

        // Then
        XCTAssertEqual(capturedRequests.count, 2)
        XCTAssertEqual(capturedRequests[0].url, capturedRequests[1].url)
        XCTAssertEqual(capturedRequests[0].allHTTPHeaderFields, capturedRequests[1].allHTTPHeaderFields)
        XCTAssertEqual(capturedRequests[0].httpBody, capturedRequests[1].httpBody)
        assertSuccess(capturedResult)
    }

    func testRetriesTransientHTTPStatuses() {
        for statusCode in [408, 500, 503, 599] {
            let scheduler = ManualScheduler()
            var fetchCount = 0
            let operation = makeOperation(
                retryCount: 1,
                fetch: { _, completion in
                    fetchCount += 1
                    completion(.success(Self.response(statusCode: fetchCount == 1 ? statusCode : 200)))
                    return {}
                },
                schedule: scheduler.schedule,
                jitter: { _ in 0 }
            )
            var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

            operation.start { capturedResult = $0 }
            scheduler.runNext()

            XCTAssertEqual(fetchCount, 2, "status: \(statusCode)")
            assertSuccess(capturedResult, message: "status: \(statusCode)")
        }
    }

    func testDoesNotRetryNonTransientHTTPStatuses() {
        for statusCode in [400, 401, 404, 429, 600] {
            let scheduler = ManualScheduler()
            var fetchCount = 0
            let operation = makeOperation(
                retryCount: 10,
                fetch: { _, completion in
                    fetchCount += 1
                    completion(.success(Self.response(statusCode: statusCode)))
                    return {}
                },
                schedule: scheduler.schedule
            )
            var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

            operation.start { capturedResult = $0 }

            XCTAssertEqual(fetchCount, 1, "status: \(statusCode)")
            XCTAssertTrue(scheduler.activeDelays.isEmpty, "status: \(statusCode)")
            assertHTTPStatus(
                capturedResult,
                statusCode: statusCode,
                message: "a retry decorator must return the final HTTP response unchanged"
            )
        }
    }

    func testRetriesURLTransportErrors() {
        let retryableErrors: [URLError] = [
            URLError(.timedOut),
            URLError(.notConnectedToInternet),
            URLError(.networkConnectionLost)
        ]

        for error in retryableErrors {
            let scheduler = ManualScheduler()
            var fetchCount = 0
            let operation = makeOperation(
                retryCount: 1,
                fetch: { _, completion in
                    fetchCount += 1
                    if fetchCount == 1 {
                        completion(.failure(error))
                    } else {
                        completion(.success(Self.response(statusCode: 200)))
                    }
                    return {}
                },
                schedule: scheduler.schedule,
                jitter: { _ in 0 }
            )
            var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

            operation.start { capturedResult = $0 }
            scheduler.runNext()

            XCTAssertEqual(fetchCount, 2, "error: \(error.code)")
            assertSuccess(capturedResult, message: "error: \(error.code)")
        }
    }

    func testDoesNotRetryCancellationOrNonURLError() {
        let nonRetryableErrors: [Error] = [
            URLError(.cancelled),
            NSError(domain: "test", code: 1)
        ]

        for error in nonRetryableErrors {
            let scheduler = ManualScheduler()
            var fetchCount = 0
            let operation = makeOperation(
                retryCount: 10,
                fetch: { _, completion in
                    fetchCount += 1
                    completion(.failure(error))
                    return {}
                },
                schedule: scheduler.schedule
            )

            operation.start { _ in }

            XCTAssertEqual(fetchCount, 1)
            XCTAssertTrue(scheduler.activeDelays.isEmpty)
        }
    }

    func testEachAttemptTimesOutAfterFullBodyWaitAndCancelsItsTask() {
        // A URLSession data-task completion represents receipt of the complete response body.
        // Holding these completions simulates a body that never finishes downloading.
        let scheduler = ManualScheduler()
        var fetchCompletions: [(Result<FlagAssignmentsFetchResponse, Error>) -> Void] = []
        var cancellationCount = 0
        var completionCount = 0
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                fetchCompletions.append(completion)
                return { cancellationCount += 1 }
            },
            timeout: 1,
            schedule: scheduler.schedule,
            jitter: { _ in 0 }
        )

        operation.start { result in
            completionCount += 1
            capturedResult = result
        }

        XCTAssertEqual(fetchCompletions.count, 1)
        XCTAssertEqual(scheduler.activeDelays, [1])
        scheduler.runNext() // first attempt timeout
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(scheduler.activeDelays, [0])

        fetchCompletions[0](.failure(URLError(.cancelled))) // late callback from cancelled task
        XCTAssertEqual(completionCount, 0)
        scheduler.runNext() // retry delay

        XCTAssertEqual(fetchCompletions.count, 2)
        XCTAssertEqual(scheduler.activeDelays, [1])
        scheduler.runNext() // second attempt timeout

        XCTAssertEqual(cancellationCount, 2)
        XCTAssertEqual(completionCount, 1)
        assertURLFailure(capturedResult, code: .timedOut)

        fetchCompletions[1](.success(Self.response(statusCode: 200)))
        XCTAssertEqual(completionCount, 1, "late task completion must be ignored")
    }

    func testZeroTimeoutDisablesTimer() {
        let scheduler = ManualScheduler()
        let operation = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                completion(.success(Self.response(statusCode: 200)))
                return {}
            },
            timeout: 0,
            schedule: scheduler.schedule
        )
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

        operation.start { capturedResult = $0 }

        assertSuccess(capturedResult)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
    }

    func testUsesBoundedExponentialFullJitter() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        var jitterUpperBounds: [TimeInterval] = []
        let operation = makeOperation(
            retryCount: 10,
            fetch: { _, completion in
                fetchCount += 1
                if fetchCount <= 10 {
                    completion(.failure(URLError(.notConnectedToInternet)))
                } else {
                    completion(.success(Self.response(statusCode: 200)))
                }
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { upperBound in
                jitterUpperBounds.append(upperBound)
                return upperBound / 2
            }
        )
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

        operation.start { capturedResult = $0 }
        for _ in 0..<10 {
            scheduler.runNext()
        }

        XCTAssertEqual(fetchCount, 11)
        XCTAssertEqual(jitterUpperBounds, [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8, 25.6, 30])
        assertSuccess(capturedResult)
    }

    func test503RetryAfterIsAddedAsBoundedFloor() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                fetchCount += 1
                completion(
                    .success(
                        Self.response(
                            statusCode: fetchCount == 1 ? 503 : 200,
                            headers: fetchCount == 1 ? ["retry-after": "5"] : nil
                        )
                    )
                )
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { $0 / 2 }
        )
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?

        operation.start { capturedResult = $0 }

        XCTAssertEqual(scheduler.activeDelays, [5.05])
        scheduler.runNext()
        assertSuccess(capturedResult)
    }

    func test503RetryAfterHTTPDateUsesCurrentTime() {
        let scheduler = ManualScheduler()
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let retryDate = now.addingTimeInterval(20)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                completion(
                    .success(
                        Self.response(
                            statusCode: 503,
                            headers: ["Retry-After": formatter.string(from: retryDate)]
                        )
                    )
                )
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { _ in 0 },
            now: { now }
        )

        operation.start { _ in }

        XCTAssertEqual(scheduler.activeDelays, [20])
    }

    func test503RetryAfterAbove30SecondsIsNotRetried() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        var capturedResult: Result<FlagAssignmentsFetchResponse, Error>?
        let operation = makeOperation(
            retryCount: 10,
            fetch: { _, completion in
                fetchCount += 1
                completion(.success(Self.response(statusCode: 503, headers: ["Retry-After": "31"])))
                return {}
            },
            schedule: scheduler.schedule
        )

        operation.start { capturedResult = $0 }

        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(scheduler.activeDelays.isEmpty)
        assertHTTPStatus(capturedResult, statusCode: 503)
    }

    func testMalformedRetryAfterUsesJitterOnly() {
        let scheduler = ManualScheduler()
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                completion(.success(Self.response(statusCode: 503, headers: ["Retry-After": "1.5"])))
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { $0 / 2 }
        )

        operation.start { _ in }

        XCTAssertEqual(scheduler.activeDelays, [0.05])
    }

    func testTransportCompletionIsDeliveredExactlyOnce() {
        var completionCount = 0
        let operation = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                completion(.success(Self.response(statusCode: 200)))
                completion(.failure(URLError(.notConnectedToInternet)))
                return {}
            }
        )

        operation.start { _ in completionCount += 1 }

        XCTAssertEqual(completionCount, 1)
    }

    private func makeOperation(
        retryCount: Int,
        fetch: @escaping FlagAssignmentsFetch,
        request: URLRequest = URLRequest(url: .mockAny()),
        timeout: TimeInterval = 0,
        schedule: @escaping FlagAssignmentsSchedule = FlagAssignmentsRequestOperation.schedule,
        jitter: @escaping (TimeInterval) -> TimeInterval = { _ in 0 },
        now: @escaping () -> Date = Date.init
    ) -> FlagAssignmentsRequestOperation {
        FlagAssignmentsRequestOperation(
            request: request,
            timeout: timeout,
            retryCount: retryCount,
            fetch: fetch,
            schedule: schedule,
            jitter: jitter,
            now: now
        )
    }

    private static func response(
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> FlagAssignmentsFetchResponse {
        FlagAssignmentsFetchResponse(
            data: Data(),
            httpResponse: HTTPURLResponse(
                url: .mockAny(),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
        )
    }

    private func assertURLFailure(
        _ result: Result<FlagAssignmentsFetchResponse, Error>?,
        code: URLError.Code,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            case .failure(let error) = result,
            (error as? URLError)?.code == code
        else {
            return XCTFail("Expected URL error \(code)", file: file, line: line)
        }
    }

    private func assertHTTPStatus(
        _ result: Result<FlagAssignmentsFetchResponse, Error>?,
        statusCode: Int,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(let response) = result else {
            return XCTFail("Expected an HTTP response. \(message)", file: file, line: line)
        }
        XCTAssertEqual(response.httpResponse.statusCode, statusCode, message, file: file, line: line)
    }

    private func assertSuccess(
        _ result: Result<FlagAssignmentsFetchResponse, Error>?,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let result else {
            return XCTFail("Expected a result. \(message)", file: file, line: line)
        }
        XCTAssertNoThrow(try result.get(), message, file: file, line: line)
    }
}

private final class ManualScheduler {
    private final class ScheduledOperation {
        let delay: TimeInterval
        let operation: () -> Void
        var isCancelled = false
        var hasRun = false

        init(delay: TimeInterval, operation: @escaping () -> Void) {
            self.delay = delay
            self.operation = operation
        }
    }

    private var operations: [ScheduledOperation] = []

    var scheduledDelays: [TimeInterval] {
        operations.map(\.delay)
    }

    var activeDelays: [TimeInterval] {
        operations
            .filter { !$0.isCancelled && !$0.hasRun }
            .map(\.delay)
    }

    func schedule(
        after delay: TimeInterval,
        operation: @escaping () -> Void
    ) -> () -> Void {
        let scheduled = ScheduledOperation(delay: delay, operation: operation)
        operations.append(scheduled)
        return { scheduled.isCancelled = true }
    }

    func runNext(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let scheduled = operations.first(where: { !$0.isCancelled && !$0.hasRun }) else {
            return XCTFail("No scheduled operation", file: file, line: line)
        }
        scheduled.hasRun = true
        scheduled.operation()
    }
}
