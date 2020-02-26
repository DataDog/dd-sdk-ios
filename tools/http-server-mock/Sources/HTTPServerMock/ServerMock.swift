/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

public class ServerMock {
    internal let baseURL: URL

    // MARK: - Public

    public init(serverProcess: ServerProcess) {
        self.baseURL = serverProcess.serverURL
    }

    /// Retrieves session object providing unique server url to capture only a subset of requests.
    public func obtainUniqueRecordingSession() throws -> ServerSession {
        return ServerSession(server: self)
    }

    // MARK: - Endpoints

    /// Info about single request recorded by the server.
    internal struct RequestInfo: Codable {
        /// Original path of the request, i.e. `/something/1` for `POST /something/1`.
        let path: String
        /// HTTP method of this request.
        let httpMethod: String
        /// Follow-up path to fetch HTTP body associated with this request.
        let httpBodyInspectionPath: String

        enum CodingKeys: String, CodingKey {
            case path = "request_path"
            case httpMethod = "request_method"
            case httpBodyInspectionPath = "inspection_path"
        }
    }

    /// Fetches info about all `POST` requests recorded by the server.
    internal func getRecordedPOSTRequestsInfo() throws -> [RequestInfo] {
        let inspectionEndpointURL = baseURL.appendingPathComponent("/inspect")
        let inspectionData = try Data(contentsOf: inspectionEndpointURL)
        return try JSONDecoder()
            .decode([RequestInfo].self, from: inspectionData)
            .filter { $0.httpMethod == "POST" }
    }

    /// Fetches HTTP body of particular request recorded by the server.
    internal func getRecordedRequestBody(_ requestInfo: RequestInfo) throws -> Data {
        let bodyURL = baseURL.appendingPathComponent(requestInfo.httpBodyInspectionPath)
        return try Data(contentsOf: bodyURL)
    }
}
