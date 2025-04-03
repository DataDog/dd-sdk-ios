/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
@testable import DatadogCore

internal class HTTPClientMock: HTTPClient {
    /// The queue to synchronise access to tracked requests.
    private let queue = DispatchQueue(label: "com.datadoghq.HTTPClientMock-\(UUID().uuidString)")
    /// Keeps track of sent requests.
    private var requests: [URLRequest] = []
    /// Closure providing the result for each request.
    private let result: (URLRequest) -> Result<HTTPURLResponse, Error>

    /// Initializes the mock client with a result closure.
    /// - Parameter result: Closure providing the completion result for each incoming request (default is a successful HTTP response with `202` code).
    init(result: @escaping ((URLRequest) -> Result<HTTPURLResponse, Error>) = { _ in .success(.mockResponseWith(statusCode: 202)) }) {
        self.result = result
    }

    /// Convenience initializer for creating a mock client with a predefined response.
    /// - Parameter response: `HTTPURLResponse` to be used as completion for all incoming requests.
    convenience init(response: HTTPURLResponse) {
        self.init(result: { _ in .success(response) })
    }

    /// Convenience initializer for creating a mock client with a predefined response code.
    /// - Parameter responseCode: HTTP status code to be used as completion for all incoming requests.
    convenience init(responseCode: Int) {
        self.init(response: .mockResponseWith(statusCode: responseCode))
    }

    /// Convenience initializer for creating a mock client with a predefined error.
    /// - Parameter error: Error to be used as completion for all incoming requests.
    convenience init(error: Error) {
        self.init(result: { _ in .failure(error) })
    }

    // MARK: - HTTPClient conformance

    func send(request: URLRequest, delegate: URLSessionTaskDelegate?, completion: @escaping (Result<HTTPURLResponse, any Error>) -> Void) {
        queue.async {
            completion(self.result(request))
            self.requests.append(request)
        }
    }

    // MARK: - Tracked requests retrieval

    /// Retrieves the tracked requests.
    /// - Returns: An array of tracked URLRequest instances.
    /// - Throws: An error if decompression fails.
    func requestsSent() -> [URLRequest] {
        queue.sync {
            self.requests
        }
    }
}
