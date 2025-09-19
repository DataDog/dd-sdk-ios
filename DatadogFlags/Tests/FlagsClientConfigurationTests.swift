/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags
@testable import DatadogInternal

final class FlagsClientConfigurationTests: XCTestCase {
    func testFlagsClientConfiguration() {
        let config = FlagsClient.Configuration(
            baseURL: "https://custom.example.com"
        )

        XCTAssertEqual(config.baseURL, "https://custom.example.com")
    }

    func testFlagsClientConfigurationDefaults() {
        let config = FlagsClient.Configuration()

        XCTAssertNil(config.baseURL)
        XCTAssertTrue(config.customHeaders.isEmpty)
        XCTAssertNil(config.flaggingProxy)
    }

    func testFlagsClientConfigurationWithAllParameters() {
        let customHeaders = ["X-Custom": "value", "X-Test": "test"]
        let config = FlagsClient.Configuration(
            baseURL: "https://custom.example.com",
            customHeaders: customHeaders,
            flaggingProxy: "proxy.example.com"
        )

        XCTAssertEqual(config.baseURL, "https://custom.example.com")
        XCTAssertEqual(config.customHeaders, customHeaders)
        XCTAssertEqual(config.flaggingProxy, "proxy.example.com")
    }
}
