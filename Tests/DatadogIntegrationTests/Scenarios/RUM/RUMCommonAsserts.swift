/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import HTTPServerMock

/// A set of common assertions for all RUM tests.
protocol RUMCommonAsserts {
    /// Asserts that RUM requests are sent using expected path and HTTP headers.
    func assertHTTPHeadersAndPath(in requests: [ServerSession.POSTRequestDetails], file: StaticString, line: UInt)
}

extension RUMCommonAsserts {
    func assertHTTPHeadersAndPath(
        in requests: [ServerSession.POSTRequestDetails],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        requests.forEach { request in
            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?ddsource=ios&batch_time=1576404000000&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:1.3.0-beta3,env:integration`
            let pathRegexp = #"^(.*)(\/ui-tests-client-token\?ddsource=ios&batch_time=)([0-9]+)(&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:)([0-9].[0-9].[0-9]([-a-z0-9])*)(,env:integration)$"#
            XCTAssertNotNil(
                request.path.range(of: pathRegexp, options: .regularExpression, range: nil, locale: nil),
                """
                Request path doesn't match the expected regexp.
                ✉️ path: \(request.path)
                🧪 expected regexp:  \(pathRegexp)
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
