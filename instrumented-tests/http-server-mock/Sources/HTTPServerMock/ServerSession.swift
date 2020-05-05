/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Server session object to capture only requests send to `session.recordingURL`.
public class ServerSession {
    /// Details of a recorded request.
    public struct POSTRequestDetails {
        /// Original path of the request, i.e. `/something/1` for `POST /something/1`.
        public let path: String
        /// Original http headers of this request.
        public let httpHeaders: [String]
        /// Original body of this request.
        public let httpBody: Data
    }

    private let server: ServerMock
    private let sessionIdentifier: String

    /// Unique session URL. `POST` requests send using this base URL can be later retrieved
    /// using `getRecordedPOSTRequests()`.
    public let recordingURL: URL

    internal init(server: ServerMock) {
        self.server = server
        self.sessionIdentifier = UUID().uuidString
        self.recordingURL = server.baseURL.appendingPathComponent(sessionIdentifier)
    }

    /// Fetches details of all `POST` requests recorded by the server during this session.
    public func getRecordedPOSTRequests() throws -> [POSTRequestDetails] {
        return try server
            .getRecordedPOSTRequestsInfo() // get all recorded requests info
            .filter { requestInfo in requestInfo.path.contains(sessionIdentifier) } // narrow it to this session
            .map { requestInfo in
                return POSTRequestDetails(
                    path: requestInfo.path,
                    httpHeaders: try server.getRecordedRequestHeaders(requestInfo),
                    httpBody: try server.getRecordedRequestBody(requestInfo)
                )
            }
    }
}
