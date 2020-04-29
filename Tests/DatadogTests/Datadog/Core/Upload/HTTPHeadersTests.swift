/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class HTTPHeadersTests: XCTestCase {
    func testContentTypeHeader() {
        let applicationJSON = HTTPHeaders.HTTPHeader.contentTypeHeader(contentType: .applicationJSON)
        XCTAssertEqual(applicationJSON.field, "Content-Type")
        XCTAssertEqual(applicationJSON.value, "application/json")

        let plainText = HTTPHeaders.HTTPHeader.contentTypeHeader(contentType: .textPlainUTF8)
        XCTAssertEqual(plainText.field, "Content-Type")
        XCTAssertEqual(plainText.value, "text/plain;charset=UTF-8")
    }

    func testUserAgentHeader() {
        var userAgent = HTTPHeaders.HTTPHeader.userAgentHeader(
            for: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1"),
            appName: "FoobarApp",
            appVersion: "1.2.3"
        )
        XCTAssertEqual(userAgent.field, "User-Agent")
        XCTAssertEqual(userAgent.value, "FoobarApp/1.2.3 CFNetwork (iPhone; iOS/13.3.1)")

        userAgent = HTTPHeaders.HTTPHeader.userAgentHeader(
            for: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1"),
            appName: nil,
            appVersion: nil
        )
        XCTAssertEqual(userAgent.field, "User-Agent")
        XCTAssertEqual(userAgent.value, "Datadog/\(sdkVersion) CFNetwork (iPhone; iOS/13.3.1)")
    }

    func testComposingHeaders() {
        let headers = HTTPHeaders(
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    for: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1"),
                    appName: "FoobarApp",
                    appVersion: "1.2.3"
                )
            ]
        )

        XCTAssertEqual(
            headers.all,
            [
                "Content-Type": "application/json",
                "User-Agent": "FoobarApp/1.2.3 CFNetwork (iPhone; iOS/13.3.1)"
            ]
        )
    }
}
