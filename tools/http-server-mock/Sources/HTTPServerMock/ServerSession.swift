/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Server session object to capture only requests send to `session.recordingURL`.
public class ServerSession {
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

    /// Returns all requests recorded by the server in this session.
    public func getRecordedRequests() throws -> [Request] {
        return try server
            .getRecordedRequests() // get all recorded requests info
            .filter { request in request.path.contains(sessionIdentifier) } // narrow it to this session
    }

    /// Actively fetches requests recorded by the server in this session until given `condition` evaluated to `true`.
    /// Throws an exception if given `timeout` is exceeded.
    public func pullRecordedRequests(
        timeout: TimeInterval,
        file: StaticString = #fileID,
        line: UInt = #line,
        until condition: ([Request]) throws -> Bool
    ) throws -> [Request] {
        let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timeoutTimer.setEventHandler { timeoutTimer.cancel() }
        timeoutTimer.schedule(deadline: .now() + timeout, leeway: .nanoseconds(0))
        if #available(iOS 10.0, *) {
            timeoutTimer.activate()
        }

        var pulledRequests: [Request] = []
        var conditionMet = false
        repeat {
            pulledRequests = try getRecordedRequests()
            conditionMet = try condition(pulledRequests)
            Thread.sleep(forTimeInterval: 0.2)
        } while !(timeoutTimer.isCancelled || conditionMet)

        if timeoutTimer.isCancelled {
            throw Exception(
                description: """
                Exceeded \(timeout)s timeout with pulling \(pulledRequests.count) requests and not meeting the `condition()`.
                - pulled endpoint: \(recordingURL.absoluteString)
                - caller: \(file):\(line)
                """
            )
        } else {
            timeoutTimer.cancel()
            return pulledRequests
        }
    }
}
