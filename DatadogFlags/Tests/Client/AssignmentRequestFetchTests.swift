/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogFlags

final class AssignmentRequestFetchTests: XCTestCase {
    func testCallerCanComposeOwnWrapperUsingPublicInvocation() throws {
        let receivedRequest = LockedBox<URLRequest?>(nil)
        let cancellationCount = LockedBox(0)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { request, completion in
            receivedRequest.value = request
            completion(.success(mockAssignmentResponse()))
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let wrapped = Flags.AssignmentRequestFetch { request, completion in
            var request = request
            request.setValue("wrapper-value", forHTTPHeaderField: "X-Caller-Wrapper")
            return base(request, completion: completion)
        }

        let cancel = wrapped(URLRequest(url: .mockAny())) { capturedResult.value = $0 }

        XCTAssertEqual(receivedRequest.value?.value(forHTTPHeaderField: "X-Caller-Wrapper"), "wrapper-value")
        _ = try XCTUnwrap(capturedResult.value).get()
        cancel()
        XCTAssertEqual(cancellationCount.value, 1, "a caller-authored wrapper must preserve cancellation")
    }

    func testTimeoutCancelsFetchAndCompletesOnce() throws {
        let scheduler = ManualAssignmentRequestScheduler()
        let fetchCompletion = LockedBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let cancellationCount = LockedBox(0)
        let completionCount = LockedBox(0)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            fetchCompletion.value = completion
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let fetch = base.withTimeout(1, schedule: scheduler.makeSchedule())

        _ = fetch(URLRequest(url: .mockAny())) { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }
        scheduler.runNext()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertEqual(try XCTUnwrap(capturedResult.value).failureURLCode, .timedOut)

        fetchCompletion.value?(.success(mockAssignmentResponse()))
        XCTAssertEqual(completionCount.value, 1, "a late transport callback must be ignored")
    }

    func testSynchronousCompletionCancelsReturnedTransportHandleWithoutSchedulingTimeout() throws {
        let scheduler = ManualAssignmentRequestScheduler()
        let cancellationCount = LockedBox(0)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(mockAssignmentResponse()))
            return { cancellationCount.mutate { $0 += 1 } }
        }

        _ = base.withTimeout(1, schedule: scheduler.makeSchedule())(URLRequest(url: .mockAny())) {
            capturedResult.value = $0
        }

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertTrue(scheduler.delays.isEmpty)
        _ = try XCTUnwrap(capturedResult.value).get()
    }

    func testCancellationStopsFetchAndTimerWithoutCompleting() {
        let scheduler = ManualAssignmentRequestScheduler()
        let fetchCancellationCount = LockedBox(0)
        let completionCount = LockedBox(0)
        let base = Flags.AssignmentRequestFetch { _, _ in
            return { fetchCancellationCount.mutate { $0 += 1 } }
        }
        let cancel = base.withTimeout(1, schedule: scheduler.makeSchedule())(URLRequest(url: .mockAny())) { _ in
            completionCount.mutate { $0 += 1 }
        }

        cancel()
        scheduler.runNext()

        XCTAssertEqual(fetchCancellationCount.value, 1)
        XCTAssertEqual(completionCount.value, 0)
        XCTAssertTrue(scheduler.delays.isEmpty)
    }

    func testDisabledAndInvalidTimeoutsLeaveTransportUnchanged() throws {
        for timeout in [0, -1, .nan, .infinity] {
            let scheduler = ManualAssignmentRequestScheduler()
            let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
            let base = Flags.AssignmentRequestFetch { _, completion in
                completion(.success(mockAssignmentResponse()))
                return {}
            }

            _ = base.withTimeout(timeout, schedule: scheduler.makeSchedule())(URLRequest(url: .mockAny())) {
                capturedResult.value = $0
            }

            XCTAssertTrue(scheduler.delays.isEmpty, "timeout: \(timeout)")
            _ = try XCTUnwrap(capturedResult.value).get()
        }
    }

    func testTimeoutIsCappedAtSupportedTimerRange() {
        let scheduler = ManualAssignmentRequestScheduler()
        let base = Flags.AssignmentRequestFetch { _, _ in {} }

        let cancel = base.withTimeout(.greatestFiniteMagnitude, schedule: scheduler.makeSchedule())(
            URLRequest(url: .mockAny())
        ) { _ in }

        XCTAssertEqual(scheduler.delays, [2_147_483.647])
        cancel()
        XCTAssertTrue(scheduler.delays.isEmpty)
    }

    func testTimeoutThatFiresDuringTimerRegistrationCompletesOnce() throws {
        let cancellationCount = LockedBox(0)
        let completionCount = LockedBox(0)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, _ in
            return { cancellationCount.mutate { $0 += 1 } }
        }
        let schedule: AssignmentRequestSchedule = { _, work in
            work()
            return { cancellationCount.mutate { $0 += 1 } }
        }

        _ = base.withTimeout(1, schedule: schedule)(URLRequest(url: .mockAny())) { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }

        XCTAssertEqual(cancellationCount.value, 2, "both transport and consumed timer handles must be cancelled")
        XCTAssertEqual(completionCount.value, 1)
        XCTAssertEqual(try XCTUnwrap(capturedResult.value).failureURLCode, .timedOut)
    }

    func testDefaultScheduleCancellationPreventsTimeoutCompletion() {
        let transportCancellationCount = LockedBox(0)
        let completion = expectation(description: "timeout completion")
        completion.isInverted = true
        let base = Flags.AssignmentRequestFetch { _, _ in
            return { transportCancellationCount.mutate { $0 += 1 } }
        }

        let cancel = base.withTimeout(0.1)(URLRequest(url: .mockAny())) { _ in
            completion.fulfill()
        }
        cancel()

        wait(for: [completion], timeout: 0.2)
        XCTAssertEqual(transportCancellationCount.value, 1)
    }

    func testDefaultScheduleDefersTimeoutByRequestedDelay() throws {
        let requestedDelay: TimeInterval = 0.1
        let startedAt = Date()
        let elapsed = LockedBox<TimeInterval?>(nil)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let completed = expectation(description: "timeout completed")
        let base = Flags.AssignmentRequestFetch { _, _ in {} }

        _ = base.withTimeout(requestedDelay)(URLRequest(url: .mockAny())) { result in
            elapsed.value = Date().timeIntervalSince(startedAt)
            capturedResult.value = result
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(elapsed.value), requestedDelay)
        XCTAssertEqual(try XCTUnwrap(capturedResult.value).failureURLCode, .timedOut)
    }

    func testCompletedOperationIsNotRetainedByTimerOrCancellation() {
        let scheduler = ManualAssignmentRequestScheduler()
        let fetchCompletion = LockedBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let cancellation = LockedBox<Flags.AssignmentRequestFetch.Cancellation?>(nil)
        weak var weakProbe: AssignmentRequestFetchLifetimeProbe?

        autoreleasepool {
            let probe = AssignmentRequestFetchLifetimeProbe()
            weakProbe = probe
            let base = Flags.AssignmentRequestFetch { [probe] _, completion in
                _ = probe
                fetchCompletion.value = completion
                return {}
            }
            let fetch = base.withTimeout(1, schedule: scheduler.makeSchedule())

            cancellation.value = fetch(URLRequest(url: .mockAny())) { _ in }
            fetchCompletion.value?(.success(mockAssignmentResponse()))
            fetchCompletion.value = nil
        }

        XCTAssertNotNil(cancellation.value)
        XCTAssertNil(weakProbe)
        XCTAssertTrue(scheduler.delays.isEmpty)
        withExtendedLifetime(cancellation.value) {}
    }

    func testTransportCompletionIsDeliveredExactlyOnce() throws {
        let completionCount = LockedBox(0)
        let capturedResult = LockedBox<Result<Flags.AssignmentRequestFetch.Response, Error>?>(nil)
        let base = Flags.AssignmentRequestFetch { _, completion in
            completion(.success(mockAssignmentResponse()))
            completion(.failure(URLError(.notConnectedToInternet)))
            return {}
        }

        _ = base.withTimeout(1)(URLRequest(url: .mockAny())) { result in
            completionCount.mutate { $0 += 1 }
            capturedResult.value = result
        }

        XCTAssertEqual(completionCount.value, 1)
        _ = try XCTUnwrap(capturedResult.value).get()
    }

    func testConcurrentTimeoutAndTransportCompletionCompleteExactlyOnce() {
        for _ in 0..<100 {
            let timeoutWork = LockedBox<(@Sendable () -> Void)?>(nil)
            let fetchCompletion = LockedBox<Flags.AssignmentRequestFetch.Completion?>(nil)
            let completionCount = LockedBox(0)
            let schedule: AssignmentRequestSchedule = { _, work in
                timeoutWork.value = work
                return {}
            }
            let base = Flags.AssignmentRequestFetch { _, completion in
                fetchCompletion.value = completion
                return {}
            }

            _ = base.withTimeout(1, schedule: schedule)(URLRequest(url: .mockAny())) { _ in
                completionCount.mutate { $0 += 1 }
            }

            let race = DispatchGroup()
            DispatchQueue.global().async(group: race) {
                timeoutWork.value?()
            }
            DispatchQueue.global().async(group: race) {
                fetchCompletion.value?(.success(mockAssignmentResponse()))
            }

            XCTAssertEqual(race.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(completionCount.value, 1)
        }
    }
}

private final class ManualAssignmentRequestScheduler: @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let delay: TimeInterval
        let work: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var delays: [TimeInterval] {
        lock.withLock { entries.map(\.delay) }
    }

    func makeSchedule() -> AssignmentRequestSchedule {
        return { [self] delay, work in
            let id = UUID()
            lock.withLock {
                entries.append(Entry(id: id, delay: delay, work: work))
            }
            return { [weak self] in
                self?.lock.withLock {
                    self?.entries.removeAll { $0.id == id }
                }
            }
        }
    }

    func runNext() {
        let work = lock.withLock {
            entries.isEmpty ? nil : entries.removeFirst().work
        }
        work?()
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }

    func mutate(_ operation: (inout Value) -> Void) {
        lock.withLock { operation(&storedValue) }
    }
}

private final class AssignmentRequestFetchLifetimeProbe {}

private extension Result where Success == Flags.AssignmentRequestFetch.Response, Failure == Error {
    var failureURLCode: URLError.Code? {
        guard case .failure(let error) = self else {
            return nil
        }
        return (error as? URLError)?.code
    }
}

private func mockAssignmentResponse(
    statusCode: Int = 200,
    data: Data = .mockAnyFlagAssignmentsResponse()
) -> Flags.AssignmentRequestFetch.Response {
    let url = URL.mockAny()
    return .init(
        data: data,
        httpResponse: HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    )
}
