/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DatadogInternal

internal typealias FlagAssignmentsFetchResponse = Flags.AssignmentRequestFetch.Response

internal typealias FlagAssignmentsFetch = (
    URLRequest,
    @escaping (Result<FlagAssignmentsFetchResponse, Error>) -> Void
) -> () -> Void

internal typealias FlagAssignmentsSchedule = (
    TimeInterval,
    @escaping () -> Void
) -> () -> Void

/// Executes an assignment request with a per-attempt timeout and bounded retries.
///
/// Each attempt receives the same immutable `URLRequest`. The operation ignores late transport
/// callbacks after a timeout and guarantees that its completion is delivered at most once.
internal final class FlagAssignmentsRequestOperation {
    internal static let maximumSupportedTimeout: TimeInterval = 2_147_483.647
    internal static let maximumRetryCount = 10

    private enum Constants {
        static let initialBackoff: TimeInterval = 0.1
        static let maxBackoff: TimeInterval = 30
        static let maxRetryAfter: TimeInterval = 30
    }

    private struct ActiveAttempt {
        let id: UInt64
        let number: Int
        var cancelFetch: (() -> Void)?
        var cancelTimeout: (() -> Void)?
    }

    private struct ScheduledRetry {
        let id: UInt64
        let nextAttemptNumber: Int
        var cancel: (() -> Void)?
    }

    private struct State {
        var isStarted = false
        var isComplete = false
        var nextAttemptID: UInt64 = 0
        var nextRetryID: UInt64 = 0
        var activeAttempt: ActiveAttempt?
        var scheduledRetry: ScheduledRetry?
        var completion: ((Result<FlagAssignmentsFetchResponse, Error>) -> Void)?
    }

    private let request: URLRequest
    private let timeout: TimeInterval
    private let retryCount: Int
    private let fetch: FlagAssignmentsFetch
    private let schedule: FlagAssignmentsSchedule
    private let jitter: (TimeInterval) -> TimeInterval
    private let now: () -> Date

    @ReadWriteLock
    private var state = State()

    init(
        request: URLRequest,
        timeout: TimeInterval,
        retryCount: Int,
        fetch: @escaping FlagAssignmentsFetch,
        schedule: @escaping FlagAssignmentsSchedule,
        jitter: @escaping (TimeInterval) -> TimeInterval,
        now: @escaping () -> Date
    ) {
        self.request = request
        self.timeout = timeout
        self.retryCount = retryCount
        self.fetch = fetch
        self.schedule = schedule
        self.jitter = jitter
        self.now = now
    }

    @discardableResult
    func start(
        completion: @escaping (Result<FlagAssignmentsFetchResponse, Error>) -> Void
    ) -> () -> Void {
        var shouldStart = false
        _state.mutate { state in
            guard !state.isStarted else {
                return
            }
            state.isStarted = true
            state.completion = completion
            shouldStart = true
        }
        guard shouldStart else {
            return {}
        }

        startAttempt(number: 0)
        return { [self] in cancel() }
    }

    private func startAttempt(number: Int) {
        guard let attemptID = activateAttempt(number: number) else {
            return
        }

        let cancelFetch = fetch(request) { [self] result in
            completeAttempt(withID: attemptID, result: result)
        }
        setFetchCancellation(cancelFetch, forAttemptWithID: attemptID)

        if timeout > 0, isAttemptActive(withID: attemptID) {
            let cancelTimeout = schedule(timeout) { [self] in
                timeOutAttempt(withID: attemptID)
            }
            guard setTimeoutCancellation(cancelTimeout, forAttemptWithID: attemptID) else {
                cancelTimeout()
                return
            }
        }
    }

    private func activateAttempt(number: Int) -> UInt64? {
        var attemptID: UInt64?
        _state.mutate { state in
            guard !state.isComplete, state.activeAttempt == nil else {
                return
            }
            state.nextAttemptID += 1
            attemptID = state.nextAttemptID
            state.activeAttempt = ActiveAttempt(
                id: state.nextAttemptID,
                number: number
            )
        }
        return attemptID
    }

    private func setTimeoutCancellation(
        _ cancellation: @escaping () -> Void,
        forAttemptWithID attemptID: UInt64
    ) -> Bool {
        var didSet = false
        _state.mutate { state in
            guard state.activeAttempt?.id == attemptID else {
                return
            }
            state.activeAttempt?.cancelTimeout = cancellation
            didSet = true
        }
        return didSet
    }

    private func isAttemptActive(withID attemptID: UInt64) -> Bool {
        state.activeAttempt?.id == attemptID
    }

    private func setFetchCancellation(
        _ cancellation: @escaping () -> Void,
        forAttemptWithID attemptID: UInt64
    ) {
        _state.mutate { state in
            if state.activeAttempt?.id == attemptID {
                state.activeAttempt?.cancelFetch = cancellation
            }
        }
    }

    private func completeAttempt(
        withID attemptID: UInt64,
        result: Result<FlagAssignmentsFetchResponse, Error>
    ) {
        guard let attempt = takeAttempt(withID: attemptID) else {
            return
        }
        attempt.cancelTimeout?()
        handle(result, afterAttempt: attempt.number)
    }

    private func timeOutAttempt(withID attemptID: UInt64) {
        guard let attempt = takeAttempt(withID: attemptID) else {
            return
        }
        cancelFetch(for: attempt)
        handle(.failure(URLError(.timedOut)), afterAttempt: attempt.number)
    }

    private func cancelFetch(for attempt: ActiveAttempt) {
        attempt.cancelFetch?()
    }

    private func takeAttempt(withID attemptID: UInt64) -> ActiveAttempt? {
        var attempt: ActiveAttempt?
        _state.mutate { state in
            guard state.activeAttempt?.id == attemptID else {
                return
            }
            attempt = state.activeAttempt
            state.activeAttempt = nil
        }
        return attempt
    }

    private func handle(
        _ result: Result<FlagAssignmentsFetchResponse, Error>,
        afterAttempt attempt: Int
    ) {
        switch result {
        case .success(let response):
            guard !(200..<300).contains(response.httpResponse.statusCode) else {
                finish(with: .success(response))
                return
            }

            guard attempt < retryCount, Self.isRetryable(response.httpResponse) else {
                finish(with: .success(response))
                return
            }

            let retryAfter = Self.retryAfterDelay(
                for: response.httpResponse,
                now: now()
            )
            guard retryAfter.map({ $0 <= Constants.maxRetryAfter }) ?? true else {
                finish(with: .success(response))
                return
            }
            scheduleRetry(afterAttempt: attempt, retryAfter: retryAfter)

        case .failure(let error):
            guard attempt < retryCount, Self.isRetryable(error) else {
                finish(with: .failure(error))
                return
            }
            scheduleRetry(afterAttempt: attempt, retryAfter: nil)
        }
    }

    private func scheduleRetry(
        afterAttempt attempt: Int,
        retryAfter: TimeInterval?
    ) {
        let maximumBackoff = min(
            Constants.initialBackoff * pow(2, TimeInterval(attempt)),
            Constants.maxBackoff
        )
        let randomBackoff = min(
            max(jitter(maximumBackoff), 0),
            maximumBackoff
        )
        let delay = (retryAfter ?? 0) + randomBackoff
        guard let retryID = activateRetry(nextAttemptNumber: attempt + 1) else {
            return
        }
        let cancellation = schedule(delay) { [self] in
            startScheduledRetry(withID: retryID)
        }
        setRetryCancellation(cancellation, forRetryWithID: retryID)
    }

    private func finish(with result: Result<FlagAssignmentsFetchResponse, Error>) {
        var completion: ((Result<FlagAssignmentsFetchResponse, Error>) -> Void)?
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.isComplete = true
            completion = state.completion
            state.completion = nil
        }
        completion?(result)
    }

    private func cancel() {
        var activeAttempt: ActiveAttempt?
        var cancelRetry: (() -> Void)?
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.isComplete = true
            state.completion = nil
            activeAttempt = state.activeAttempt
            state.activeAttempt = nil
            cancelRetry = state.scheduledRetry?.cancel
            state.scheduledRetry = nil
        }
        if let activeAttempt {
            activeAttempt.cancelTimeout?()
            cancelFetch(for: activeAttempt)
        }
        cancelRetry?()
    }

    private func activateRetry(nextAttemptNumber: Int) -> UInt64? {
        var retryID: UInt64?
        _state.mutate { state in
            guard !state.isComplete, state.activeAttempt == nil, state.scheduledRetry == nil else {
                return
            }
            state.nextRetryID += 1
            retryID = state.nextRetryID
            state.scheduledRetry = ScheduledRetry(
                id: state.nextRetryID,
                nextAttemptNumber: nextAttemptNumber
            )
        }
        return retryID
    }

    private func setRetryCancellation(
        _ cancellation: @escaping () -> Void,
        forRetryWithID retryID: UInt64
    ) {
        var shouldCancel = false
        _state.mutate { state in
            if state.scheduledRetry?.id == retryID {
                state.scheduledRetry?.cancel = cancellation
            } else if state.isComplete {
                shouldCancel = true
            }
        }
        if shouldCancel {
            cancellation()
        }
    }

    private func startScheduledRetry(withID retryID: UInt64) {
        var nextAttemptNumber: Int?
        _state.mutate { state in
            guard !state.isComplete, state.scheduledRetry?.id == retryID else {
                return
            }
            nextAttemptNumber = state.scheduledRetry?.nextAttemptNumber
            state.scheduledRetry = nil
        }
        if let nextAttemptNumber {
            startAttempt(number: nextAttemptNumber)
        }
    }

    private static func isRetryable(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 408 || (500...599).contains(response.statusCode)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code != URLError.cancelled.rawValue
    }

    private static func retryAfterDelay(
        for response: HTTPURLResponse,
        now: Date
    ) -> TimeInterval? {
        guard
            response.statusCode == 503,
            let headerValue = response.allHeaderFields.first(where: { header in
                guard let name = header.key as? String else {
                    return false
                }
                return name.caseInsensitiveCompare("Retry-After") == .orderedSame
            })?.value as? String
        else {
            return nil
        }

        let value = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.allSatisfy(\.isNumber), let seconds = TimeInterval(value) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(date.timeIntervalSince(now), 0)
            }
        }
        return nil
    }

    internal static func schedule(
        after delay: TimeInterval,
        operation: @escaping () -> Void
    ) -> () -> Void {
        let work = DispatchWorkItem(block: operation)
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: work
        )
        return work.cancel
    }
}
