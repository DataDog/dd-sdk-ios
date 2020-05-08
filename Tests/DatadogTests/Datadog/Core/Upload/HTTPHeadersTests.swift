/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class HTTPHeadersTests: XCTestCase {
    func testWhenRunningOnMobileDevice_itCreatesExpectedHeaders() {
        let headers = HTTPHeaders(
            appContext: .mockWith(
                bundleVersion: "1.0.0",
                bundleName: "app-name",
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )

        XCTAssertEqual(
            headers.all,
            [
            "Content-Type": "application/json",
            "User-Agent": "app-name/1.0.0 CFNetwork (iPhone; iOS/13.3.1)"
            ]
        )
    }

    func testWhenRunningOnOtherDevice_itCreatesExpectedHeaders() {
        let headers = HTTPHeaders(
            appContext: .mockWith(mobileDevice: nil)
        )

        XCTAssertEqual(
            headers.all,
            ["Content-Type": "application/json",]
        )
    }
}
