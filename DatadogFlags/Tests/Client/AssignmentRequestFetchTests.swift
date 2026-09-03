/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogFlags

final class AssignmentRequestFetchTests: XCTestCase {
    func testCallerCanComposeOwnWrapperUsingPublicInvocation() {
        let receivedRequest = ThreadSafeBox<URLRequest?>(nil)
        let cancellationCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { request, completion in
            receivedRequest.value = request
            completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let wrapped = Flags.AssignmentRequestFetch { request, completion in
            var request = request
            request.setValue("wrapper-value", forHTTPHeaderField: "X-Caller-Wrapper")
            return base(request, completion: completion)
        }

        let cancel = wrapped(URLRequest(url: .mockAny())) { capturedResult.value = $0 }

        XCTAssertEqual(receivedRequest.value?.value(forHTTPHeaderField: "X-Caller-Wrapper"), "wrapper-value")
        XCTAssertFlagAssignmentsSuccess(capturedResult.value)
        cancel()
        XCTAssertEqual(cancellationCount.value, 1, "a caller-authored wrapper must preserve cancellation")
    }

    func testTimeoutInsideRetryAppliesFreshTimeoutToEachAttempt() {
        let timeoutScheduler = ManualScheduler()
        let retryScheduler = ManualScheduler()
        let capturedRequests = ThreadSafeBox<[URLRequest]>([])
        let fetchCompletions = ThreadSafeBox<[Flags.AssignmentRequestFetch.Completion]>([])
        let cancellationCount = ThreadSafeBox(0)
        let completionCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { request, completion in
            capturedRequests.mutate { $0.append(request) }
            fetchCompletions.mutate { $0.append(completion) }
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let fetch = base
            .withTimeout(1, schedule: timeoutScheduler.schedule)
            .withRetry(1, schedule: retryScheduler.schedule, jitter: { _ in 0 }, now: { Date() })
        let request = URLRequest(url: .mockAny())

        _ = fetch(request) { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }

        XCTAssertEqual(capturedRequests.value.count, 1)
        XCTAssertEqual(timeoutScheduler.activeDelays, [1])
        timeoutScheduler.runNext()
        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(retryScheduler.activeDelays, [0])
        retryScheduler.runNext()
        XCTAssertEqual(capturedRequests.value.count, 2)
        guard capturedRequests.value.count == 2, fetchCompletions.value.count == 2 else {
            return XCTFail("Expected two attempts")
        }
        XCTAssertEqual(capturedRequests.value[0].url, request.url)
        XCTAssertEqual(capturedRequests.value[1].url, request.url)
        XCTAssertEqual(timeoutScheduler.activeDelays, [1])

        fetchCompletions.value[0](.failure(URLError(.cancelled)))
        XCTAssertEqual(completionCount.value, 0)
        timeoutScheduler.runNext()

        XCTAssertEqual(cancellationCount.value, 2)
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertFlagAssignmentsURLFailure(capturedResult.value, code: .timedOut)

        fetchCompletions.value[1](.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        XCTAssertEqual(completionCount.value, 1, "late completion must not escape a timed-out attempt")
    }

    func testRetryInsideTimeoutAppliesOneTimeoutToEntirePipeline() {
        let timeoutScheduler = ManualScheduler()
        let retryScheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let secondAttemptCompletion = ThreadSafeBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let secondAttemptCancellationCount = ThreadSafeBox(0)
        let completionCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            let attempt = fetchCount.mutate { count -> Int in
                count += 1
                return count
            }
            if attempt == 1 {
                completion(.failure(URLError(.networkConnectionLost)))
                return {}
            }
            secondAttemptCompletion.value = completion
            return { secondAttemptCancellationCount.mutate { $0 += 1 } }
        }
        let fetch = base
            .withRetry(1, schedule: retryScheduler.schedule, jitter: { _ in 0 }, now: { Date() })
            .withTimeout(1, schedule: timeoutScheduler.schedule)

        _ = fetch(URLRequest(url: .mockAny())) { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }

        XCTAssertEqual(timeoutScheduler.scheduledDelays, [1])
        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertEqual(retryScheduler.activeDelays, [0])
        retryScheduler.runNext()
        XCTAssertEqual(fetchCount.value, 2)
        XCTAssertEqual(timeoutScheduler.scheduledDelays, [1], "the outer timeout is not recreated per retry")

        timeoutScheduler.runNext()

        XCTAssertEqual(secondAttemptCancellationCount.value, 1)
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertFlagAssignmentsURLFailure(capturedResult.value, code: .timedOut)

        secondAttemptCompletion.value?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        XCTAssertEqual(completionCount.value, 1, "cancellation and a late callback must complete exactly once")
    }

    func testZeroTimeoutDecoratorLeavesTransportUnchanged() {
        let scheduler = ManualScheduler()
        let cancellationCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let fetch = base.withTimeout(0, schedule: scheduler.schedule)

        let cancel = fetch(URLRequest(url: .mockAny())) { capturedResult.value = $0 }

        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
        XCTAssertFlagAssignmentsSuccess(capturedResult.value)
        cancel()
        XCTAssertEqual(cancellationCount.value, 1)
    }

    func testInvalidTimeoutDecoratorDoesNotScheduleTimer() {
        for timeout in [-1, .nan, .infinity] {
            let scheduler = ManualScheduler()
            let fetchCount = ThreadSafeBox(0)
            let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
            let base = Flags.AssignmentRequestFetch { _, completion in
                fetchCount.mutate { $0 += 1 }
                completion(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
                return {}
            }
            let fetch = base.withTimeout(timeout, schedule: scheduler.schedule)

            _ = fetch(URLRequest(url: .mockAny())) { capturedResult.value = $0 }

            XCTAssertEqual(fetchCount.value, 1, "timeout: \(timeout)")
            XCTAssertTrue(scheduler.scheduledDelays.isEmpty, "timeout: \(timeout)")
            XCTAssertFlagAssignmentsSuccess(capturedResult.value, message: "timeout: \(timeout)")
        }
    }

    func testTimeoutDecoratorCapsTimerRange() {
        let scheduler = ManualScheduler()
        let base = Flags.AssignmentRequestFetch { _, _ in {} }
        let fetch = base.withTimeout(.greatestFiniteMagnitude, schedule: scheduler.schedule)

        let cancel = fetch(URLRequest(url: .mockAny())) { _ in }

        XCTAssertEqual(scheduler.activeDelays, [FlagAssignmentsRequestOperation.maximumSupportedTimeout])
        cancel()
        XCTAssertTrue(scheduler.activeDelays.isEmpty)
    }

    func testRetryDecoratorSchedulesNoRetryBeyondTheMaximumRetryCount() {
        let scheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount.mutate { $0 += 1 }
            completion(.failure(URLError(.networkConnectionLost)))
            return {}
        }
        let fetch = base.withRetry(.max, schedule: scheduler.schedule, jitter: { _ in 0 }, now: { Date() })

        _ = fetch(URLRequest(url: .mockAny())) { capturedResult.value = $0 }
        for _ in 0..<FlagAssignmentsRequestOperation.maximumRetryCount {
            scheduler.runNext()
        }

        XCTAssertEqual(fetchCount.value, FlagAssignmentsRequestOperation.maximumRetryCount + 1)
        XCTAssertTrue(scheduler.activeDelays.isEmpty)
        XCTAssertFlagAssignmentsURLFailure(capturedResult.value, code: .networkConnectionLost)
    }

    func testNegativeRetryDecoratorDoesNotRetry() {
        let scheduler = ManualScheduler()
        let fetchCount = ThreadSafeBox(0)
        let capturedResult = ThreadSafeBox<Result<FlagAssignmentsFetchResponse, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount.mutate { $0 += 1 }
            completion(.failure(URLError(.networkConnectionLost)))
            return {}
        }
        let fetch = base.withRetry(-1, schedule: scheduler.schedule, jitter: { _ in 0 }, now: { Date() })

        _ = fetch(URLRequest(url: .mockAny())) { capturedResult.value = $0 }

        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
        XCTAssertFlagAssignmentsURLFailure(capturedResult.value, code: .networkConnectionLost)
    }
}
