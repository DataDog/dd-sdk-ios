/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogConfigurationTests: XCTestCase {
    private typealias Configuration = Datadog.Configuration

    func testDefaultConfiguration() {
        let defaultConfiguration = Configuration.builderUsing(clientToken: "abcd").build()
        XCTAssertEqual(
            defaultConfiguration.logsUploadURL?.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testInvalidConfiguration() {
        let invalidConfiguration = Configuration.builderUsing(clientToken: "").build()
        XCTAssertNil(invalidConfiguration.logsUploadURL)
    }

    // MARK: - Logs endpoint

    func testUSLogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd").set(logsEndpoint: .us).build().logsUploadURL?.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testEULogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd").set(logsEndpoint: .eu).build().logsUploadURL?.url,
            URL(string: "https://mobile-http-intake.logs.datadoghq.eu/v1/input/abcd?ddsource=mobile")!
        )
    }

    func testCustomLogsEndpoint() {
        XCTAssertEqual(
            Configuration.builderUsing(clientToken: "abcd")
                .set(logsEndpoint: .custom(url: "https://api.example.com/v1/logs/"))
                .build().logsUploadURL?.url,
            URL(string: "https://api.example.com/v1/logs/abcd?ddsource=mobile")!
        )
    }
}
