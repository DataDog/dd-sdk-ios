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

internal typealias AssignmentRequestSchedule = @Sendable (
    TimeInterval,
    @escaping @Sendable () -> Void
) -> @Sendable () -> Void

private final class AssignmentRequestScheduledWork: @unchecked Sendable {
    let workItem: DispatchWorkItem

    init(operation: @escaping @Sendable () -> Void) {
        workItem = DispatchWorkItem(block: operation)
    }
}

private final class AssignmentRequestTimeoutOperation: @unchecked Sendable {
    static let maximumSupportedTimeout: TimeInterval = 2_147_483.647

    private struct State {
        var isStarted = false
        var isComplete = false
        var cancelFetch: Flags.AssignmentRequestFetch.Cancellation?
        var cancelTimeout: Flags.AssignmentRequestFetch.Cancellation?
        var completion: Flags.AssignmentRequestFetch.Completion?
        var keepAlive: AssignmentRequestTimeoutOperation?
    }

    private let request: URLRequest
    private let timeout: TimeInterval
    private let fetch: Flags.AssignmentRequestFetch
    private let schedule: AssignmentRequestSchedule

    @ReadWriteLock
    private var state = State()

    init(
        request: URLRequest,
        timeout: TimeInterval,
        fetch: Flags.AssignmentRequestFetch,
        schedule: @escaping AssignmentRequestSchedule
    ) {
        self.request = request
        self.timeout = timeout
        self.fetch = fetch
        self.schedule = schedule
    }

    @discardableResult
    func start(
        completion: @escaping Flags.AssignmentRequestFetch.Completion
    ) -> Flags.AssignmentRequestFetch.Cancellation {
        var shouldStart = false
        _state.mutate { state in
            guard !state.isStarted else {
                return
            }
            state.isStarted = true
            state.completion = completion
            state.keepAlive = self
            shouldStart = true
        }
        guard shouldStart else {
            return {}
        }

        let cancelFetch = fetch(request) { [self] result in
            finish(with: result)
        }
        setFetchCancellation(cancelFetch)

        if isActive {
            let cancelTimeout = schedule(timeout) { [weak self] in
                self?.timeOut()
            }
            setTimeoutCancellation(cancelTimeout)
        }

        return { [weak self] in self?.cancel() }
    }

    private var isActive: Bool {
        !state.isComplete
    }

    private func setFetchCancellation(
        _ cancellation: @escaping Flags.AssignmentRequestFetch.Cancellation
    ) {
        var didSet = false
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.cancelFetch = cancellation
            didSet = true
        }
        if !didSet {
            cancellation()
        }
    }

    private func setTimeoutCancellation(
        _ cancellation: @escaping Flags.AssignmentRequestFetch.Cancellation
    ) {
        var didSet = false
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.cancelTimeout = cancellation
            didSet = true
        }
        if !didSet {
            cancellation()
        }
    }

    private func timeOut() {
        var cancelFetch: Flags.AssignmentRequestFetch.Cancellation?
        var completion: Flags.AssignmentRequestFetch.Completion?
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.isComplete = true
            cancelFetch = state.cancelFetch
            state.cancelFetch = nil
            state.cancelTimeout = nil
            completion = state.completion
            state.completion = nil
            state.keepAlive = nil
        }
        cancelFetch?()
        completion?(.failure(URLError(.timedOut)))
    }

    private func finish(
        with result: Result<Flags.AssignmentRequestFetch.Response, Error>
    ) {
        var cancelTimeout: Flags.AssignmentRequestFetch.Cancellation?
        var completion: Flags.AssignmentRequestFetch.Completion?
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.isComplete = true
            cancelTimeout = state.cancelTimeout
            state.cancelTimeout = nil
            state.cancelFetch = nil
            completion = state.completion
            state.completion = nil
            state.keepAlive = nil
        }
        cancelTimeout?()
        completion?(result)
    }

    private func cancel() {
        var cancelFetch: Flags.AssignmentRequestFetch.Cancellation?
        var cancelTimeout: Flags.AssignmentRequestFetch.Cancellation?
        _state.mutate { state in
            guard !state.isComplete else {
                return
            }
            state.isComplete = true
            cancelFetch = state.cancelFetch
            cancelTimeout = state.cancelTimeout
            state.cancelFetch = nil
            state.cancelTimeout = nil
            state.completion = nil
            state.keepAlive = nil
        }
        cancelTimeout?()
        cancelFetch?()
    }

    static func boundedTimeout(_ timeout: TimeInterval) -> TimeInterval? {
        guard timeout.isFinite, timeout > 0 else {
            return nil
        }
        return min(timeout, maximumSupportedTimeout)
    }

    static let schedule: AssignmentRequestSchedule = { delay, work in
        let scheduledWork = AssignmentRequestScheduledWork(operation: work)
        DispatchQueue.global().asyncAfter(
            deadline: .now() + delay,
            execute: scheduledWork.workItem
        )
        return { scheduledWork.workItem.cancel() }
    }
}

extension Flags {
    /// A transport for precomputed flag-assignment requests.
    ///
    /// The SDK builds the complete request before it passes the request to this transport.
    public struct AssignmentRequestFetch: Sendable {
        /// The response returned by an assignment-request transport.
        public struct Response: Sendable {
            /// The complete response body.
            public let data: Data

            /// The HTTP response metadata.
            public let httpResponse: HTTPURLResponse

            /// Creates an assignment-request response.
            public init(data: Data, httpResponse: HTTPURLResponse) {
                self.data = data
                self.httpResponse = httpResponse
            }
        }

        /// Completion callback for an assignment request.
        public typealias Completion = @Sendable (Result<Response, Error>) -> Void

        /// Requests cancellation of an in-flight assignment request.
        public typealias Cancellation = @Sendable () -> Void

        private let execute: @Sendable (
            URLRequest,
            @escaping Completion
        ) -> Cancellation

        /// Creates a transport from a request execution closure.
        public init(
            _ fetch: @escaping @Sendable (
                URLRequest,
                @escaping Completion
            ) -> Cancellation
        ) {
            execute = fetch
        }

        /// Executes this transport for an SDK-built assignment request.
        @discardableResult
        public func callAsFunction(
            _ request: URLRequest,
            completion: @escaping Completion
        ) -> Cancellation {
            execute(request, completion)
        }

        /// Creates the SDK's default assignment transport with an ephemeral `URLSession`.
        public static func urlSession() -> Self {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            return urlSession(URLSession(configuration: configuration))
        }

        /// Creates an assignment transport with a caller-provided `URLSession`.
        public static func urlSession(_ session: URLSession) -> Self {
            Self { request, completion in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(URLError(.badServerResponse)))
                        return
                    }
                    completion(
                        .success(
                            Response(
                                data: data ?? Data(),
                                httpResponse: httpResponse
                            )
                        )
                    )
                }
                task.resume()
                return { task.cancel() }
            }
        }

        /// Wraps this transport with a timeout for the complete response-body download.
        ///
        /// A value of zero disables the timer. Negative and non-finite values leave the transport unchanged.
        /// Values above the supported timer range are capped at `2_147_483.647` seconds.
        public func withTimeout(_ timeout: TimeInterval) -> Self {
            withTimeout(timeout, schedule: AssignmentRequestTimeoutOperation.schedule)
        }

        internal func withTimeout(
            _ timeout: TimeInterval,
            schedule: @escaping AssignmentRequestSchedule
        ) -> Self {
            guard let timeout = AssignmentRequestTimeoutOperation.boundedTimeout(timeout) else {
                return self
            }
            return Self { request, completion in
                let operation = AssignmentRequestTimeoutOperation(
                    request: request,
                    timeout: timeout,
                    fetch: self,
                    schedule: schedule
                )
                return operation.start(completion: completion)
            }
        }
    }
}
