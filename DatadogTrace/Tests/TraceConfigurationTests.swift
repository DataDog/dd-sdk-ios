/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogTrace

class TraceConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        // When
        let config = Trace.Configuration()

        // Then
        XCTAssertEqual(config.sampleRate, 100)
        XCTAssertNil(config.service)
        XCTAssertNil(config.tags)
        XCTAssertNil(config.urlSessionTracking)
        XCTAssertTrue(config.bundleWithRumEnabled)
        XCTAssertFalse(config.networkInfoEnabled)
        XCTAssertNil(config.eventMapper)
        XCTAssertNil(config.customEndpoint)
    }
}
