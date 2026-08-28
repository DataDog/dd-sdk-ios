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
        var receivedRequest: URLRequest?
        var cancellationCount = 0
        let base = Flags.AssignmentRequestFetch { request, completion in
            receivedRequest = request
            completion(.success(Self.response(statusCode: 200)))
            return { cancellationCount += 1 }
        }
        let wrapped = Flags.AssignmentRequestFetch { request, completion in
            var request = request
            request.setValue("wrapper-value", forHTTPHeaderField: "X-Caller-Wrapper")
            return base(request, completion: completion)
        }
        var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

        let cancel = wrapped(URLRequest(url: .mockAny())) { capturedResult = $0 }

        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "X-Caller-Wrapper"), "wrapper-value")
        assertSuccess(capturedResult)

        cancel()
        XCTAssertEqual(cancellationCount, 1, "a caller-authored wrapper must preserve cancellation")
    }

    func testTimeoutInsideRetryAppliesFreshTimeoutToEachAttempt() {
        // `base.withTimeout(1).withRetry(1)` is the chainable Swift equivalent of
        // `withRetry(withTimeout(base, 1), 1)`: retry invokes a fresh timeout wrapper each time.
        let scheduler = ManualScheduler()
        var capturedRequests: [URLRequest] = []
        var fetchCompletions: [Flags.AssignmentRequestFetch.Completion] = []
        var cancellationCount = 0
        let base = Flags.AssignmentRequestFetch { request, completion in
            capturedRequests.append(request)
            fetchCompletions.append(completion)
            return { cancellationCount += 1 }
        }
        let fetch = base
            .withTimeout(1, schedule: scheduler.schedule)
            .withRetry(1, schedule: scheduler.schedule, jitter: { _ in 0 }, now: Date.init)
        let request = URLRequest(url: .mockAny())
        var completionCount = 0
        var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

        _ = fetch(request) { result in
            completionCount += 1
            capturedResult = result
        }

        XCTAssertEqual(capturedRequests.count, 1)
        XCTAssertEqual(scheduler.activeDelays, [1])
        scheduler.runNext() // first attempt timeout
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(scheduler.activeDelays, [0])

        fetchCompletions[0](.failure(URLError(.cancelled))) // cancelled attempt finishes late
        XCTAssertEqual(completionCount, 0)
        scheduler.runNext() // retry backoff

        XCTAssertEqual(capturedRequests.count, 2)
        XCTAssertEqual(capturedRequests[0].url, request.url)
        XCTAssertEqual(capturedRequests[1].url, request.url)
        XCTAssertEqual(scheduler.activeDelays, [1])
        scheduler.runNext() // second attempt timeout

        XCTAssertEqual(cancellationCount, 2)
        XCTAssertEqual(completionCount, 1)
        assertURLFailure(capturedResult, code: .timedOut)

        fetchCompletions[1](.success(Self.response(statusCode: 200)))
        XCTAssertEqual(completionCount, 1, "late completion must not escape a timed-out attempt")
    }

    func testRetryInsideTimeoutAppliesOneTimeoutToEntirePipeline() {
        // Reversing the chain is intentionally different: `base.withRetry(1).withTimeout(1)`
        // wraps the entire retry pipeline in one timeout.
        let timeoutScheduler = ManualScheduler()
        let retryScheduler = ManualScheduler()
        var fetchCount = 0
        var secondAttemptCompletion: Flags.AssignmentRequestFetch.Completion?
        var secondAttemptCancellationCount = 0
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount += 1
            if fetchCount == 1 {
                completion(.failure(URLError(.networkConnectionLost)))
                return {}
            }
            secondAttemptCompletion = completion
            return { secondAttemptCancellationCount += 1 }
        }
        let fetch = base
            .withRetry(1, schedule: retryScheduler.schedule, jitter: { _ in 0 }, now: Date.init)
            .withTimeout(1, schedule: timeoutScheduler.schedule)
        var completionCount = 0
        var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

        _ = fetch(URLRequest(url: .mockAny())) { result in
            completionCount += 1
            capturedResult = result
        }

        XCTAssertEqual(timeoutScheduler.scheduledDelays, [1])
        XCTAssertEqual(retryScheduler.activeDelays, [0])
        retryScheduler.runNext()
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(timeoutScheduler.scheduledDelays, [1], "the outer timeout is not recreated per retry")

        timeoutScheduler.runNext()

        XCTAssertEqual(secondAttemptCancellationCount, 1)
        XCTAssertEqual(completionCount, 1)
        assertURLFailure(capturedResult, code: .timedOut)

        secondAttemptCompletion?(.success(Self.response(statusCode: 200)))
        XCTAssertEqual(completionCount, 1, "cancellation and a late callback must complete exactly once")
    }

    func testDisabledOrInvalidTimeoutDecoratorDoesNotScheduleTimer() {
        for timeout in [0, -1, .nan, .infinity] {
            let scheduler = ManualScheduler()
            var fetchCount = 0
            let base = Flags.AssignmentRequestFetch { _, completion in
                fetchCount += 1
                completion(.success(Self.response(statusCode: 200)))
                return {}
            }
            let fetch = base.withTimeout(timeout, schedule: scheduler.schedule)
            var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

            _ = fetch(URLRequest(url: .mockAny())) { capturedResult = $0 }

            XCTAssertEqual(fetchCount, 1, "timeout: \(timeout)")
            XCTAssertTrue(scheduler.scheduledDelays.isEmpty, "timeout: \(timeout)")
            assertSuccess(capturedResult, message: "timeout: \(timeout)")
        }
    }

    func testTimeoutDecoratorCapsTimerRange() {
        let scheduler = ManualScheduler()
        let base = Flags.AssignmentRequestFetch { _, _ in {} }
        let fetch = base.withTimeout(.greatestFiniteMagnitude, schedule: scheduler.schedule)

        let cancel = fetch(URLRequest(url: .mockAny())) { _ in }

        XCTAssertEqual(
            scheduler.activeDelays,
            [FlagAssignmentsRequestOperation.maximumSupportedTimeout]
        )
        cancel()
        XCTAssertTrue(scheduler.activeDelays.isEmpty)
    }

    func testRetryDecoratorCapsRetryCount() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount += 1
            if fetchCount <= FlagAssignmentsRequestOperation.maximumRetryCount {
                completion(.failure(URLError(.networkConnectionLost)))
            } else {
                completion(.success(Self.response(statusCode: 200)))
            }
            return {}
        }
        let fetch = base.withRetry(
            .max,
            schedule: scheduler.schedule,
            jitter: { _ in 0 },
            now: Date.init
        )
        var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

        _ = fetch(URLRequest(url: .mockAny())) { capturedResult = $0 }
        for _ in 0..<FlagAssignmentsRequestOperation.maximumRetryCount {
            scheduler.runNext()
        }

        XCTAssertEqual(fetchCount, FlagAssignmentsRequestOperation.maximumRetryCount + 1)
        assertSuccess(capturedResult)
    }

    func testNegativeRetryDecoratorDoesNotRetry() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount += 1
            completion(.failure(URLError(.networkConnectionLost)))
            return {}
        }
        let fetch = base.withRetry(
            -1,
            schedule: scheduler.schedule,
            jitter: { _ in 0 },
            now: Date.init
        )
        var capturedResult: Result<Flags.AssignmentRequestFetch.Response, Error>?

        _ = fetch(URLRequest(url: .mockAny())) { capturedResult = $0 }

        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
        assertURLFailure(capturedResult, code: .networkConnectionLost)
    }

    func testCancellingComposedFetchCancelsRetryDelayAndSuppressesLateWork() {
        let scheduler = ManualScheduler()
        var fetchCount = 0
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCount += 1
            completion(.failure(URLError(.notConnectedToInternet)))
            return {}
        }
        let fetch = base.withRetry(
            1,
            schedule: scheduler.schedule,
            jitter: { _ in 0 },
            now: Date.init
        )
        var completionCount = 0

        let cancel = fetch(URLRequest(url: .mockAny())) { _ in completionCount += 1 }
        XCTAssertEqual(scheduler.activeDelays, [0])

        cancel()

        XCTAssertTrue(scheduler.activeDelays.isEmpty)
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(fetchCount, 1)
    }

    private static func response(statusCode: Int) -> Flags.AssignmentRequestFetch.Response {
        Flags.AssignmentRequestFetch.Response(
            data: Data(),
            httpResponse: HTTPURLResponse(
                url: .mockAny(),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    private func assertURLFailure(
        _ result: Result<Flags.AssignmentRequestFetch.Response, Error>?,
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

    private func assertSuccess(
        _ result: Result<Flags.AssignmentRequestFetch.Response, Error>?,
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
