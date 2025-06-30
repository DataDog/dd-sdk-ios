/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogRUM

class RUMConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        // When
        let config = RUM.Configuration(applicationID: "app-id")

        // Then
        XCTAssertEqual(config.applicationID, "app-id")
        XCTAssertEqual(config.sessionSampleRate, 100)
        XCTAssertEqual(config.telemetrySampleRate, 20)
        XCTAssertNil(config.uiKitViewsPredicate)
        XCTAssertNil(config.uiKitActionsPredicate)
        XCTAssertNil(config.swiftUIViewsPredicate)
        XCTAssertNil(config.swiftUIActionsPredicate)
        XCTAssertNil(config.urlSessionTracking)
        XCTAssertTrue(config.trackFrustrations)
        XCTAssertFalse(config.trackBackgroundEvents)
        XCTAssertEqual(config.longTaskThreshold, 0.1)
        XCTAssertNil(config.appHangThreshold)
        XCTAssertEqual(config.vitalsUpdateFrequency, .average)
        XCTAssertNil(config.viewEventMapper)
        XCTAssertNil(config.resourceEventMapper)
        XCTAssertNil(config.actionEventMapper)
        XCTAssertNil(config.errorEventMapper)
        XCTAssertNil(config.longTaskEventMapper)
        XCTAssertNil(config.onSessionStart)
        XCTAssertNil(config.customEndpoint)
        XCTAssertTrue(config.trackAnonymousUser)
        XCTAssertTrue(config.trackMemoryWarnings)
    }
}
