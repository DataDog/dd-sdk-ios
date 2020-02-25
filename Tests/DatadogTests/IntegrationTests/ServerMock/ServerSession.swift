/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Server session object to capture only requests send to `session.recordingURL`.
class ServerSession {
    /// Details of a recorded request.
    struct POSTRequestDetails {
        /// Original path of the request, i.e. `/something/1` for `POST /something/1`.
        let path: String
        /// Original body of this request.
        let httpBody: Data
    }

    private let server: ServerMock
    private let sessionIdentifier: String

    /// Server URL unique to this session. `POST` requests send using this base URL can be later retrieved
    /// using `getRecordedPOSTRequests()`.
    let recordingURL: String

    init(server: ServerMock) {
        self.server = server
        self.sessionIdentifier = UUID().uuidString
        self.recordingURL = server.url.appendingPathComponent(sessionIdentifier).absoluteString
    }

    /// Fetches details of all `POST` requests recorded by the server during this session.
    func getRecordedPOSTRequests() throws -> [POSTRequestDetails] {
        return try server
            .getRecordedPOSTRequestsInfo() // get all recorded requests info
            .filter { requestInfo in requestInfo.path.contains(sessionIdentifier) } // narrow it to this session
            .map { requestInfo in
                return POSTRequestDetails(
                    path: requestInfo.path,
                    httpBody: try server.getRecordedRequestBody(requestInfo)
                )
            }
    }
}
