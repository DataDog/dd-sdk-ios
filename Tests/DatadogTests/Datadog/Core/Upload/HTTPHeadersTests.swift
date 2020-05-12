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
            appName: "app-name",
            appVersion: "1.0.0",
            device: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
        )

        XCTAssertEqual(
            headers.all,
            [
            "Content-Type": "application/json",
            "User-Agent": "app-name/1.0.0 CFNetwork (iPhone; iOS/13.3.1)"
            ]
        )
    }
}
