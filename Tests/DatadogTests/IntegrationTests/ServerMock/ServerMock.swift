/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

class ServerMock {
    #if os(macOS) && DD_SDK_DEVELOPMENT
    /// For convenience, when testing locally on macOS, mock server is started automatically.
    /// When testing on iOS Simulator, the server must be started manually by running `/tools/server-mock/run-server-mock.py`.
    private let serverProcess: ServerMockProcess = .runUntilDeallocated()
    #endif

    /// Base url of the server.
    let url = URL(string: "http://localhost:8000")!

    /// Retrieves session object providing unique server url to capture only a subset of requests.
    func obtainUniqueRecordingSession(file: StaticString = #file, line: UInt = #line) -> ServerSession {
        waitUntilServerProcessIsReachable(file: file, line: line)
        return ServerSession(server: self)
    }

    // MARK: - Fetching recorded requests

    /// Info about single request recorded by the server.
    struct RequestInfo: Codable {
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
    func getRecordedPOSTRequestsInfo() throws -> [RequestInfo] {
        let inspectionEndpointURL = url.appendingPathComponent("/inspect")
        let inspectionData = try Data(contentsOf: inspectionEndpointURL)
        return try JSONDecoder()
            .decode([RequestInfo].self, from: inspectionData)
            .filter { $0.httpMethod == "POST" }
    }

    /// Fetches HTTP body of particular request recorded by the server.
    func getRecordedRequestBody(_ requestInfo: RequestInfo) throws -> Data {
        let bodyURL = url.appendingPathComponent(requestInfo.httpBodyInspectionPath)
        return try Data(contentsOf: bodyURL)
    }

    // MARK: - Helpers

    /// Waits until server is started. Returns `false` if it failed to start within an arbitrary time.
    private func waitUntilServerProcessIsReachable(file: StaticString = #file, line: UInt = #line) {
        let deadline = Date(timeIntervalSinceNow: 3)

        while Date() < deadline {
            if ping() {
                return // OK
            }
        }

        XCTFail( "🔥 Mock server is not running. Start it using `/tools/server-mock/run-server-mock.py`.", file: file, line: line)
    }

    /// Checks if the server is running.
    private func ping() -> Bool {
        return (try? self.getRecordedPOSTRequestsInfo()) != nil
    }
}
