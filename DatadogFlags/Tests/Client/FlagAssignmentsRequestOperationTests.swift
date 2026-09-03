/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogFlags

final class FlagAssignmentsRequestOperationTests: XCTestCase {
    func testPreservesRequestAcrossDelayedRetry() {
        var request = URLRequest(url: .mockAny())
        request.setValue("custom-value", forHTTPHeaderField: "X-Custom-Header")
        request.httpBody = Data("request-body".utf8)
        let scheduler = ManualScheduler()
        let capturedRequests = ThreadSafeBox<[URLRequest]>([])
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let operation = makeOperation(
            retryCount: 1,
            fetch: { request, completion in
                let attempt = capturedRequests.mutate { requests -> Int in
                    requests.append(request)
                    return requests.count
                }
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: attempt == 1 ? 500 : 200)))
                return {}
            },
            request: request,
            schedule: scheduler.schedule,
            jitter: { _ in 0.05 }
        )

        operation.start { capturedResult.value = $0 }

        XCTAssertEqual(capturedRequests.value.count, 1)
        XCTAssertEqual(scheduler.activeDelays, [0.05])
        scheduler.runNext()
        XCTAssertEqual(capturedRequests.value.count, 2)
        XCTAssertEqual(capturedRequests.value[0].url, capturedRequests.value[1].url)
        XCTAssertEqual(capturedRequests.value[0].allHTTPHeaderFields, capturedRequests.value[1].allHTTPHeaderFields)
        XCTAssertEqual(capturedRequests.value[0].httpBody, capturedRequests.value[1].httpBody)
        XCTAssertFlagAssignmentsSuccess(capturedResult.value)
    }

    func testRetriesTransientHTTPStatusesAfterBackoff() {
        for statusCode in [408, 500, 503, 599] {
            let scheduler = ManualScheduler()
            let fetchCount = ThreadSafeBox(0)
            let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
            let operation = makeOperation(
                retryCount: 1,
                fetch: { _, completion in
                    let attempt = fetchCount.mutate { count -> Int in
                        count += 1
                        return count
                    }
                    completion(.success(mockFlagAssignmentsFetchResponse(statusCode: attempt == 1 ? statusCode : 200)))
                    return {}
                },
                schedule: scheduler.schedule,
                jitter: { _ in 0.04 }
            )

            operation.start { capturedResult.value = $0 }

            XCTAssertEqual(fetchCount.value, 1, "status: \(statusCode)")
            XCTAssertEqual(scheduler.activeDelays, [0.04], "status: \(statusCode)")
            scheduler.runNext()
            XCTAssertEqual(fetchCount.value, 2, "status: \(statusCode)")
            XCTAssertFlagAssignmentsSuccess(capturedResult.value, message: "status: \(statusCode)")
        }
    }

    func testDoesNotRetryNonTransientHTTPStatuses() {
        for statusCode in [400, 401, 404, 429, 600] {
            let scheduler = ManualScheduler()
            let fetchCount = ThreadSafeBox(0)
            let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
            let operation = makeOperation(
                retryCount: 10,
                fetch: { _, completion in
                    fetchCount.mutate { $0 += 1 }
                    completion(.success(mockFlagAssignmentsFetchResponse(statusCode: statusCode)))
                    return {}
                },
                schedule: scheduler.schedule
            )

            operation.start { capturedResult.value = $0 }

            XCTAssertEqual(fetchCount.value, 1, "status: \(statusCode)")
            XCTAssertTrue(scheduler.scheduledDelays.isEmpty, "status: \(statusCode)")
            XCTAssertFlagAssignmentsHTTPStatus(
                capturedResult.value,
                statusCode: statusCode,
                message: "a retry decorator must return the final HTTP response unchanged"
            )
        }
    }

    func testRetriesOnlyTransientURLErrors() {
        let retryableCodes: [URLError.Code] = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet
        ]

        for code in retryableCodes {
            let scheduler = ManualScheduler()
            let fetchCount = ThreadSafeBox(0)
            let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
            let operation = makeOperation(
                retryCount: 1,
                fetch: { _, completion in
                    let attempt = fetchCount.mutate { count -> Int in
                        count += 1
                        return count
                    }
                    if attempt == 1 {
                        completion(.failure(URLError(code)))
                    } else {
                        completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                    }
                    return {}
                },
                schedule: scheduler.schedule,
                jitter: { _ in 0.02 }
            )

            operation.start { capturedResult.value = $0 }
            XCTAssertEqual(scheduler.activeDelays, [0.02], "error: \(code)")
            scheduler.runNext()

            XCTAssertEqual(fetchCount.value, 2, "error: \(code)")
            XCTAssertFlagAssignmentsSuccess(capturedResult.value, message: "error: \(code)")
        }
    }

    func testDoesNotRetryPermanentURLErrorsOrNonURLError() {
        let nonRetryableErrors: [Error] = [
            URLError(.cancelled),
            URLError(.badURL),
            URLError(.unsupportedURL),
            URLError(.userAuthenticationRequired),
            URLError(.secureConnectionFailed),
            URLError(.serverCertificateUntrusted),
            URLError(.appTransportSecurityRequiresSecureConnection),
            NSError(domain: "test", code: 1)
        ]

        for error in nonRetryableErrors {
            let scheduler = ManualScheduler()
            let fetchCount = ThreadSafeBox(0)
            let operation = makeOperation(
                retryCount: 10,
                fetch: { _, completion in
                    fetchCount.mutate { $0 += 1 }
                    completion(.failure(error))
                    return {}
                },
                schedule: scheduler.schedule
            )

            operation.start { _ in }

            XCTAssertEqual(fetchCount.value, 1, "error: \(error)")
            XCTAssertTrue(scheduler.scheduledDelays.isEmpty, "error: \(error)")
        }
    }

    func testUsesFullJitterWithExponentialBackoffCappedAtThirtySeconds() {
        let scheduler = ManualScheduler()
        let observedMaximums = ThreadSafeBox<[TimeInterval]>([])
        let operation = makeOperation(
            retryCount: 10,
            fetch: { _, completion in
                completion(.failure(URLError(.networkConnectionLost)))
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { maximum in
                observedMaximums.mutate { $0.append(maximum) }
                return maximum
            }
        )

        operation.start { _ in }
        for _ in 0..<10 {
            scheduler.runNext()
        }

        XCTAssertEqual(
            observedMaximums.value,
            [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8, 25.6, 30]
        )
        XCTAssertEqual(scheduler.scheduledDelays, observedMaximums.value)
    }

    func testHTTP503HonorsRetryAfterDeltaSecondsPlusJitter() {
        let scheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                let attempt = fetchCount.mutate { count -> Int in
                    count += 1
                    return count
                }
                completion(.success(mockFlagAssignmentsFetchResponse(
                    statusCode: attempt == 1 ? 503 : 200,
                    headers: ["Retry-After": "2"]
                )))
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { _ in 0.05 }
        )

        operation.start { _ in }

        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertEqual(scheduler.activeDelays, [2.05])
        scheduler.runNext()
        XCTAssertEqual(fetchCount.value, 2)
    }

    func testHTTP503HonorsRetryAfterHTTPDatePlusJitter() {
        let scheduler = ManualScheduler()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let retryDate = formatter.string(from: now.addingTimeInterval(10))
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                completion(.success(mockFlagAssignmentsFetchResponse(
                    statusCode: 503,
                    headers: ["Retry-After": retryDate]
                )))
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { _ in 0.05 },
            now: { now }
        )

        operation.start { _ in }

        XCTAssertEqual(scheduler.activeDelays, [10.05])
    }

    func testHTTP503DoesNotRetryWhenRetryAfterExceedsThirtySeconds() {
        let scheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let operation = makeOperation(
            retryCount: 10,
            fetch: { _, completion in
                fetchCount.mutate { $0 += 1 }
                completion(.success(mockFlagAssignmentsFetchResponse(
                    statusCode: 503,
                    headers: ["Retry-After": "31"]
                )))
                return {}
            },
            schedule: scheduler.schedule
        )

        operation.start { capturedResult.value = $0 }

        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
        XCTAssertFlagAssignmentsHTTPStatus(capturedResult.value, statusCode: 503)
    }

    func testRetryAfterIsIgnoredForStatusesOtherThanHTTP503() {
        let scheduler = ManualScheduler()
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                completion(.success(mockFlagAssignmentsFetchResponse(
                    statusCode: 500,
                    headers: ["Retry-After": "20"]
                )))
                return {}
            },
            schedule: scheduler.schedule,
            jitter: { _ in 0.05 }
        )

        operation.start { _ in }

        XCTAssertEqual(scheduler.activeDelays, [0.05])
    }

    func testEachAttemptTimesOutAfterFullBodyWaitAndCancelsItsTask() {
        let scheduler = ManualScheduler()
        let fetchCompletions = ThreadSafeBox<[Flags.AssignmentRequestFetch.Completion]>([])
        let cancellationCount = ThreadSafeBox(0)
        let completionCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                fetchCompletions.mutate { $0.append(completion) }
                return { cancellationCount.mutate { $0 += 1 } }
            },
            timeout: 1,
            schedule: scheduler.schedule,
            jitter: { _ in 0 }
        )

        operation.start { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }

        XCTAssertEqual(fetchCompletions.value.count, 1)
        XCTAssertEqual(scheduler.activeDelays, [1])
        scheduler.runNext()
        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(scheduler.activeDelays, [0])
        scheduler.runNext()
        XCTAssertEqual(fetchCompletions.value.count, 2)
        XCTAssertEqual(scheduler.activeDelays, [1])

        fetchCompletions.value[0](.failure(URLError(.cancelled)))
        XCTAssertEqual(completionCount.value, 0)
        scheduler.runNext()

        XCTAssertEqual(cancellationCount.value, 2)
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertFlagAssignmentsURLFailure(capturedResult.value, code: .timedOut)

        fetchCompletions.value[1](.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        XCTAssertEqual(completionCount.value, 1, "late task completion must be ignored")
    }

    func testSynchronousTerminalCompletionCancelsFetchReturnedAfterCompletion() {
        let cancellationCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let operation = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                return { cancellationCount.mutate { $0 += 1 } }
            }
        )

        operation.start { capturedResult.value = $0 }

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertFlagAssignmentsSuccess(capturedResult.value)
    }

    func testSynchronousRetryableCompletionCancelsEachFetchReturnedAfterCompletion() {
        let scheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let cancellationCount = ThreadSafeBox(0)
        let operation = makeOperation(
            retryCount: 1,
            fetch: { _, completion in
                let attempt = fetchCount.mutate { count -> Int in
                    count += 1
                    return count
                }
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: attempt == 1 ? 500 : 200)))
                return { cancellationCount.mutate { $0 += 1 } }
            },
            schedule: scheduler.schedule,
            jitter: { _ in 0 }
        )

        operation.start { _ in }

        XCTAssertEqual(cancellationCount.value, 1)
        scheduler.runNext()
        XCTAssertEqual(fetchCount.value, 2)
        XCTAssertEqual(cancellationCount.value, 2)
    }

    func testNoTimeoutDoesNotScheduleTimer() {
        let scheduler = ManualScheduler()
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let operation = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                return {}
            },
            timeout: nil,
            schedule: scheduler.schedule
        )

        operation.start { capturedResult.value = $0 }

        XCTAssertFlagAssignmentsSuccess(capturedResult.value)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
    }

    func testCompletedOperationIsNotRetainedByTimerOrCancellation() {
        let scheduler = ManualScheduler()
        let fetchCompletion = ThreadSafeBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let cancellation = ThreadSafeBox<Flags.AssignmentRequestFetch.Cancellation?>(nil)
        weak var weakOperation: FlagAssignmentsRequestOperation?
        var operation: FlagAssignmentsRequestOperation? = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                fetchCompletion.value = completion
                return {}
            },
            timeout: FlagAssignmentsRequestOperation.maximumSupportedTimeout,
            schedule: scheduler.schedule
        )
        weakOperation = operation

        cancellation.value = operation?.start { _ in }
        fetchCompletion.value?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        fetchCompletion.value = nil
        operation = nil

        XCTAssertNotNil(cancellation.value)
        XCTAssertNil(weakOperation)
        withExtendedLifetime(cancellation.value) {}
    }

    func testTransportCompletionIsDeliveredExactlyOnce() {
        let completionCount = ThreadSafeBox(0)
        let operation = makeOperation(
            retryCount: 0,
            fetch: { _, completion in
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                completion(.failure(URLError(.notConnectedToInternet)))
                return {}
            }
        )

        operation.start { _ in completionCount.mutate { $0 += 1 } }

        XCTAssertEqual(completionCount.value, 1)
    }

    private func makeOperation(
        retryCount: Int,
        fetch: @escaping FlagAssignmentsFetch,
        request: URLRequest = URLRequest(url: .mockAny()),
        timeout: TimeInterval? = nil,
        schedule: @escaping FlagAssignmentsSchedule = FlagAssignmentsRequestOperation.schedule,
        jitter: @escaping FlagAssignmentsJitter = { _ in 0 },
        now: @escaping FlagAssignmentsNow = { Date() },
        completionQueue: DispatchQueue? = nil
    ) -> FlagAssignmentsRequestOperation {
        FlagAssignmentsRequestOperation(
            request: request,
            timeout: timeout,
            retryCount: retryCount,
            fetch: fetch,
            schedule: schedule,
            jitter: jitter,
            now: now,
            completionQueue: completionQueue
        )
    }
}
