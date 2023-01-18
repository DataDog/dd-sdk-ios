/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

internal struct Exception: Error, CustomStringConvertible {
    let description: String
}

/// Intermediate representation of the request - as it was received from the Python server.
fileprivate struct IntermediateRequest: Codable {
    /// Request method.
    let method: String
    /// Request path.
    let path: String
    /// Request headers encoded as base64 string.
    let headers: String
    /// Request body encoded as base64 string.
    let body: String
}

fileprivate extension Request {
    // MARK: - Initialization

    /// Constructs `Request` from `IntermediateRequest` received from Python server.
    init(intermediateRequest: IntermediateRequest) throws {
        guard let headersData = Data(base64Encoded: intermediateRequest.headers),
              let headersString = String(data: headersData, encoding: .utf8),
              let bodyData = Data(base64Encoded: intermediateRequest.body) else {
            throw Exception(description: "Failed to decode data retrieved from Python server.")
        }

        self.path = intermediateRequest.path
        self.httpMethod = intermediateRequest.method
        self.httpHeaders = headersString
            .split(separator: "\n")
            .map { String($0) }
        self.httpBody = bodyData
    }
}

public class ServerMock {
    internal let baseURL: URL
    private let jsonDecoder = JSONDecoder()

    // MARK: - Public

    public init(serverProcess: ServerProcess) {
        self.baseURL = serverProcess.serverURL
    }

    /// Retrieves session object providing unique server url to capture only a subset of requests.
    public func obtainUniqueRecordingSession() -> ServerSession {
        return ServerSession(server: self)
    }

    // MARK: - Endpoints

    /// Fetches all requests recorded by the server.
    internal func getRecordedRequests() throws -> [Request] {
        let inspectionEndpointURL = baseURL.appendingPathComponent("/inspect")
        let inspectionData = try Data(contentsOf: inspectionEndpointURL)
        let intermediateRequests = try jsonDecoder
            .decode([IntermediateRequest].self, from: inspectionData)

        return try intermediateRequests
            .map { try Request(intermediateRequest: $0) }
    }
}
