/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock

/// TODO: RUMM-742 Replace this workaround with a nicer way.
protocol RUMM742Workaround {
    /// Pulls requests from the mock server until given `condition` is met.
    func pullRecordedRUMRequests(
        from serverSession: ServerSession,
        until condition: (RUMSessionMatcher) -> Bool
    ) throws -> [ServerSession.POSTRequestDetails]
}

extension RUMM742Workaround {
    func pullRecordedRUMRequests(
        from serverSession: ServerSession,
        until condition: (RUMSessionMatcher) -> Bool
    ) throws -> [ServerSession.POSTRequestDetails] {
        return try pullRecordedRUMRequests(count: 1, from: serverSession, until: condition)
    }

    private func pullRecordedRUMRequests(
        count: Int,
        from serverSession: ServerSession,
        until condition: (RUMSessionMatcher) -> Bool
    ) throws -> [ServerSession.POSTRequestDetails] {
        let requests = try serverSession.pullRecordedPOSTRequests(count: count, timeout: 30)
        let matchers = try requests.flatMap { try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData($0.httpBody) }
        let session = try RUMSessionMatcher.groupMatchersBySessions(matchers).first!

        if condition(session) {
            return requests
        } else if count + 1 < 4 { // try 4 requests at max
            return try pullRecordedRUMRequests(count: count + 1, from: serverSession, until: condition)
        } else {
            fatalError("Pulled 4 requests, without matching the `condition()`.")
        }
    }
}
