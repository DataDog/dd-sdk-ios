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

    internal struct Exception: Error, CustomStringConvertible {
        let description: String
    }

    private let server: ServerMock
    private let sessionIdentifier: String

    /// Unique session URL. `POST` requests send using this base URL can be later retrieved
    /// using `getRecordedPOSTRequests() or pullRecordedPOSTRequests()`.
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

    /// Actively fetches 'POST` requests recorded by the server until a desired count is found, or timeouts returning current recorded requests
    public func pullRecordedPOSTRequests(count: Int, timeout: TimeInterval) throws -> [POSTRequestDetails] {
        var currentRequests = [ServerMock.RequestInfo]()

        let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timeoutTimer.setEventHandler { timeoutTimer.cancel() }
        timeoutTimer.schedule(deadline: .now() + timeout, leeway: .nanoseconds(0))
        if #available(iOS 10.0, *) {
            timeoutTimer.activate()
        }

        repeat {
            currentRequests = try server
                .getRecordedPOSTRequestsInfo()
                .filter { requestInfo in requestInfo.path.contains(sessionIdentifier) }
            Thread.sleep(forTimeInterval: 0.2)
        } while !timeoutTimer.isCancelled && currentRequests.count < count

        if timeoutTimer.isCancelled {
            throw Exception(description: "Exceeded \(timeout)s timeout by receiving only \(currentRequests.count) requests, where \(count) were expected.")
        } else {
            timeoutTimer.cancel()
        }

        return try currentRequests.map { requestInfo in
            return POSTRequestDetails(
                path: requestInfo.path,
                httpHeaders: try server.getRecordedRequestHeaders(requestInfo),
                httpBody: try server.getRecordedRequestBody(requestInfo)
            )
        }
    }
}
