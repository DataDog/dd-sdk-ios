/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import HTTPServerMock
import XCTest

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

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309?ddsource=ios&&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:1.3.0-beta3,env:integration,retry_count:1`
            XCTAssertNotNil(request.path, file: file, line: line)
            XCTAssertNotNil(request.queryItems)
            XCTAssertEqual(request.queryItems!.count, 2)
            XCTAssertEqual(request.queryItems?.value(name: "ddsource"), "ios", file: file, line: line)

            let ddtags = request.queryItems?.ddtags()
            XCTAssertNotNil(ddtags, file: file, line: line)
            XCTAssertEqual(ddtags?.count, 5, file: file, line: line)
            XCTAssertEqual(ddtags?["service"], "ui-tests-service-name", file: file, line: line)
            XCTAssertEqual(ddtags?["version"], "1.0", file: file, line: line)
            XCTAssertEqual(ddtags?["sdk_version"]?.matches(regex: semverRegex), true, file: file, line: line)
            XCTAssertEqual(ddtags?["env"], "integration", file: file, line: line)
            XCTAssertEqual(ddtags?["retry_count"], "1", file: file, line: line)

            XCTAssertEqual(request.httpHeaders["Content-Type"], "text/plain;charset=UTF-8", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["User-Agent"]?.matches(regex: userAgentRegex), true, file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-API-KEY"], "ui-tests-client-token", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-EVP-ORIGIN"], "ios", file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-EVP-ORIGIN-VERSION"]?.matches(regex: semverRegex), true, file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-REQUEST-ID"]?.matches(regex: ddRequestIDRegex), true, file: file, line: line)
            XCTAssertEqual(request.httpHeaders["DD-IDEMPOTENCY-KEY"]?.matches(regex: sha1Regex), true, file: file, line: line)
        }
    }
}

extension RUMSessionMatcher {
    /// Retrieves single RUM Session from given `requests`.
    /// - Parameter eventsPatch: optional transformation to apply on each event within the payload before instantiating matcher (default: `nil`)
    class func singleSession(from requests: [HTTPServerMock.Request], eventsPatch: ((Data) throws -> Data)? = nil) throws -> RUMSessionMatcher? {
        return try sessions(maxCount: 1, from: requests, eventsPatch: eventsPatch).first
    }

    /// Retrieves `maxCount` RUM Sessions from given `requests`.
    /// - Parameter eventsPatch: optional transformation to apply on each event within the payload before instantiating matcher (default: `nil`)
    class func sessions(maxCount: Int, from requests: [HTTPServerMock.Request], eventsPatch: ((Data) throws -> Data)? = nil) throws -> [RUMSessionMatcher] {
        let eventMatchers = try requests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody, eventsPatch: eventsPatch) }
            .filterTelemetry()
        let sessionMatchers = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers).sorted(by: {
            return $0.views.first?.viewEvents.first?.date ?? 0 < $1.views.first?.viewEvents.first?.date ?? 0
        })

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

    class func assertViewWasEventuallyInactive(_ view: View) {
        XCTAssertFalse(try XCTUnwrap(view.viewEvents.last?.view.isActive))
    }

    /// Checks if RUM session has ended by:
    /// - checking if it contains "end view" added in response to `ExampleApplication.endRUMSession()`;
    /// - checking if all other views are marked as "inactive" (meaning they ended up processing their resources).
    func hasEnded() -> Bool {
        let hasEndView = views.last?.name == Environment.Constants.rumSessionEndViewName
        let hasSomeActiveView = views.contains(where: { $0.viewEvents.last?.view.isActive == true })
        return hasEndView && !hasSomeActiveView
    }
}
