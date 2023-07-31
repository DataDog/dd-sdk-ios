/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309?ddsource=ios&&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:1.3.0-beta3,env:integration`
            let pathRegex = #"^(.*)(\?ddsource=ios&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:)\#(semverPattern)(,env:integration)$"#
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

            let expectedHeadersRegexes = [
                #"^Content-Type: text/plain;charset=UTF-8$"#,
                #"^User-Agent: .*/\d+[.\d]* CFNetwork \([a-zA-Z ]+; iOS/[0-9.]+\)$"#, // e.g. "User-Agent: Example/1.0 CFNetwork (iPhone; iOS/14.5)"
                #"^DD-API-KEY: ui-tests-client-token$"#,
                #"^DD-EVP-ORIGIN: ios$"#,
                #"^DD-EVP-ORIGIN-VERSION: \#(semverPattern)$"#, // e.g. "DD-EVP-ORIGIN-VERSION: 1.7.0-beta.2"
                #"^DD-REQUEST-ID: [0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"# // e.g. "DD-REQUEST-ID: 524A2616-D2AA-4FE5-BBD9-898D173BE658"
            ]
            expectedHeadersRegexes.forEach { expectedHeaderRegex in
                XCTAssertTrue(
                    request.httpHeaders.contains { $0.matches(regex: expectedHeaderRegex) },
                    """
                    Request doesn't contain header matching expected regex.
                    ✉️ request headers: \(request.httpHeaders.joined(separator: "\n"))
                    🧪 expected regex: '\(expectedHeaderRegex)'
                    """,
                    file: file,
                    line: line
                )
            }
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
            .filter { event in try event.eventType() != "telemetry" }
        let sessionMatchers = try RUMSessionMatcher.groupMatchersBySessions(eventMatchers).sorted(by: {
            return $0.viewVisits.first?.viewEvents.first?.date ?? 0 < $1.viewVisits.first?.viewEvents.first?.date ?? 0
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

    class func assertViewWasEventuallyInactive(_ viewVisit: ViewVisit) {
        XCTAssertFalse(try XCTUnwrap(viewVisit.viewEvents.last?.view.isActive))
    }

    /// Checks if RUM session has ended by:
    /// - checking if it contains "end view" added in response to `ExampleApplication.endRUMSession()`;
    /// - checking if all other views are marked as "inactive" (meaning they ended up processing their resources).
    func hasEnded() -> Bool {
        let hasEndView = viewVisits.last?.name == Environment.Constants.rumSessionEndViewName
        let hasSomeActiveView = viewVisits.contains(where: { $0.viewEvents.last?.view.isActive == true })
        return hasEndView && !hasSomeActiveView
    }
}
