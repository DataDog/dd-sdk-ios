/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?ddsource=ios`
            let pathRegex = #"^(.*)(/ui-tests-client-token\?ddsource=ios)$"#
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
            let expectedHeader = "Content-Type: application/json"
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

extension LogMatcher {
    class func from(requests: [HTTPServerMock.Request]) throws -> [LogMatcher] {
        return try requests
            .flatMap { request in try LogMatcher.fromArrayOfJSONObjectsData(request.httpBody) }
    }
}
