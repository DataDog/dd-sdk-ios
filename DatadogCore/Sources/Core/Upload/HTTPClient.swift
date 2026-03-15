/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines a type responsible for sending HTTP requests.
internal protocol HTTPClient: Sendable {
    /// Sends the provided request using HTTP.
    /// - Parameters:
    ///   - request: The request to be sent.
    ///   - delegate: The task-specific delegate.
    /// - Returns: The HTTP response.
    func send(request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> HTTPURLResponse
}

extension HTTPClient {
    /// Sends the provided request using HTTP without a task delegate.
    func send(request: URLRequest) async throws -> HTTPURLResponse {
        try await send(request: request, delegate: nil)
    }
}
