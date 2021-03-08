/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock

/// A set of common assertions for all RUM tests.
protocol RUMCommonAsserts {
    func assertRUM(requests: [HTTPServerMock.Request], file: StaticString, line: UInt)
}

extension RUMCommonAsserts {
    func assertRUM(
        requests: [HTTPServerMock.Request],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        requests.forEach { request in
            XCTAssertEqual(request.httpMethod, "POST")

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?ddsource=ios&&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:1.3.0-beta3,env:integration`
            let pathRegex = #"^(.*)(\/ui-tests-client-token\?ddsource=ios&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:)([0-9].[0-9].[0-9]([-a-z0-9])*)(,env:integration)$"#
            XCTAssertTrue(
                request.path.matches(regex: pathRegex),
                """
                Request path doesn't match the expected regex.
                ✉️ path: \(request.path)
                🧪 expected regex:  \(pathRegex)
                """,
                file: file,
                line: line
            )
            let expectedHeader = "Content-Type: text/plain;charset=UTF-8"
            XCTAssertTrue(
                request.httpHeaders.contains(expectedHeader),
                """
                Request doesn't contain expected header.
                ✉️ request headers: \(request.httpHeaders.joined(separator: "\n"))
                🧪 expected header:  \(expectedHeader)
                """,
                file: file,
                line: line
            )
        }
    }
}

extension RUMSessionMatcher {
    /// Retrieves single RUM Session from given `requests`.
    class func singleSession(from requests: [HTTPServerMock.Request]) throws -> RUMSessionMatcher? {
        return try sessions(maxCount: 1, from: requests).first
    }

    /// Retrieves `maxCount` RUM Sessions from given `requests`.
    class func sessions(maxCount: Int, from requests: [HTTPServerMock.Request]) throws -> [RUMSessionMatcher] {
        let eventMatchers = try requests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }
        let sessionMatchers = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers)

        if sessionMatchers.count > maxCount {
            throw Exception(
                description:
                """
                Expected to build \(maxCount) RUM Session(s) from given requests, but got \(sessionMatchers.count) instead.
                """
            )
        }

        return sessionMatchers
    }

    class func assertViewWasEventuallyInactive(_ viewVisit: ViewVisit) {
        XCTAssertFalse(try XCTUnwrap(viewVisit.viewEvents.last?.view.isActive))
    }
}
