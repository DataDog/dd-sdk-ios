/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension Flags {
    /// A transport for precomputed flag-assignment requests.
    ///
    /// The SDK builds the complete `URLRequest`, including its endpoint, authentication, headers, and body,
    /// before passing it to this transport. This transport is used only for retrieving flag assignments;
    /// exposure and evaluation uploads continue to use the SDK's own transport.
    public struct AssignmentRequestFetch {
        /// The response returned by an assignment-request transport.
        public struct Response {
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
        public typealias Completion = (Result<Response, Error>) -> Void

        /// Requests cancellation of an in-flight assignment request.
        ///
        /// The transport may subsequently complete with a cancellation error. Timeout and retry decorators
        /// ignore callbacks from attempts that they have already cancelled.
        public typealias Cancellation = () -> Void

        private let execute: FlagAssignmentsFetch

        /// Creates a transport from a request execution closure.
        ///
        /// The closure must return immediately after starting asynchronous work. It must invoke `completion`
        /// no more than once and return a closure that cancels any in-flight work.
        public init(
            _ fetch: @escaping (
                URLRequest,
                @escaping Completion
            ) -> Cancellation
        ) {
            self.execute = fetch
        }

        /// Executes this transport for an SDK-built assignment request.
        ///
        /// This public invocation point lets callers build their own wrappers around a transport before
        /// assigning it to `Flags.Configuration.assignmentRequestFetch`.
        public func callAsFunction(
            _ request: URLRequest,
            completion: @escaping Completion
        ) -> Cancellation {
            execute(request, completion)
        }

        /// Creates the SDK's default assignment transport backed by an ephemeral `URLSession`.
        ///
        /// This transport does not add a timeout or retry policy. Use `withTimeout(_:)` and
        /// `withRetry(_:)` to opt in to those policies.
        public static func urlSession() -> Self {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            return urlSession(URLSession(configuration: configuration))
        }

        /// Creates an assignment transport backed by a caller-provided `URLSession`.
        ///
        /// The session's existing configuration and delegate remain authoritative. This adapter does not
        /// modify its timeout, cache, authentication, or connectivity behavior.
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
                return task.cancel
            }
        }

        /// Wraps this transport with a timeout for each request.
        ///
        /// The timeout covers receipt of the complete response body. A value of `0` causes an immediate
        /// timeout. Negative and non-finite values leave the transport unchanged. Values above the
        /// supported timer range are capped at `2_147_483.647` seconds.
        public func withTimeout(_ timeout: TimeInterval) -> Self {
            withTimeout(
                timeout,
                schedule: FlagAssignmentsRequestOperation.schedule
            )
        }

        /// Wraps this transport with bounded retries for transient failures.
        ///
        /// The value is the number of retries after the initial attempt and is limited to `0...10`.
        /// URL transport failures, timeouts, HTTP `408`, and HTTP `5xx` responses are retried immediately.
        /// Cancellation, HTTP `429`, and other HTTP responses are not retried.
        public func withRetry(_ retries: Int) -> Self {
            withRetryPolicy(retries)
        }

        internal func withTimeout(
            _ timeout: TimeInterval,
            schedule: @escaping FlagAssignmentsSchedule
        ) -> Self {
            guard timeout.isFinite, timeout >= 0 else {
                return self
            }

            let boundedTimeout = min(
                timeout,
                FlagAssignmentsRequestOperation.maximumSupportedTimeout
            )
            return Self { request, completion in
                let operation = FlagAssignmentsRequestOperation(
                    request: request,
                    timeout: boundedTimeout,
                    retryCount: 0,
                    fetch: { request, completion in
                        self(request, completion: completion)
                    },
                    schedule: schedule
                )
                return operation.start(completion: completion)
            }
        }

        private func withRetryPolicy(_ retries: Int) -> Self {
            let boundedRetries = min(max(retries, 0), FlagAssignmentsRequestOperation.maximumRetryCount)
            guard boundedRetries > 0 else {
                return self
            }

            return Self { request, completion in
                let operation = FlagAssignmentsRequestOperation(
                    request: request,
                    timeout: nil,
                    retryCount: boundedRetries,
                    fetch: { request, completion in
                        self(request, completion: completion)
                    },
                    schedule: FlagAssignmentsRequestOperation.schedule
                )
                return operation.start(completion: completion)
            }
        }
    }
}
