/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import HTTPServerMock

/// A set of common assertions for all Logging tests.
protocol LoggingCommonAsserts {
    func assertLogging(requests: [HTTPServerMock.Request], file: StaticString, line: UInt)
}

extension LoggingCommonAsserts {
    func assertLogging(
        requests: [HTTPServerMock.Request],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        requests.forEach { request in
            XCTAssertEqual(request.httpMethod, "POST")

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309?ddsource=ios`
            let pathRegex = #"^(.*)(\?ddsource=ios)$"#
            XCTAssertTrue(
                request.path.matches(regex: pathRegex),
                """
                Request path doesn't match the expected regex.
                ✉️ path: \(request.path)
                🧪 expected regex: \(pathRegex)
                """,
                file: file,
                line: line
            )

            let expectedHeadersRegexes = [
                #"^Content-Type: application/json$"#,
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

extension LogMatcher {
    class func from(requests: [HTTPServerMock.Request]) throws -> [LogMatcher] {
        return try requests
            .flatMap { request in try LogMatcher.fromArrayOfJSONObjectsData(request.httpBody) }
    }
}
