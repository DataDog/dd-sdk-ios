/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class ImmutableRequestTests: XCTestCase {
    func testReadingURL() {
        let original: URLRequest = .mockWith(url: "https://example.com")
        let immutable = ImmutableRequest(request: original)
        XCTAssertEqual(immutable.url, original.url)
    }

    func testReadingHTTPMethod() {
        let original: URLRequest = .mockWith(httpMethod: .mockRandom())
        let immutable = ImmutableRequest(request: original)
        XCTAssertEqual(immutable.httpMethod, original.httpMethod)
    }

    func testReadingDatadogOriginHeader() {
        let expectedValue: String = .mockRandom(length: 128)
        let original: URLRequest = .mockWith(
            headers: [
                TracingHTTPHeaders.originField: expectedValue
            ]
        )
        let immutable = ImmutableRequest(request: original)
        XCTAssertEqual(immutable.ddOriginHeaderValue, expectedValue)
    }

    func testPreservingUnsafeOriginal() {
        let original: URLRequest = .mockAny()
        let immutable = ImmutableRequest(request: original)
        XCTAssertEqual(immutable.unsafeOriginal, original)
    }
}
