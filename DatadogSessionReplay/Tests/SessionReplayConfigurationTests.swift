/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogSessionReplay

class SessionReplayConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let random: Float = .mockRandom(min: 0, max: 100)

        // When
        let config = SessionReplay.Configuration(replaySampleRate: random)

        // Then
        XCTAssertEqual(config.replaySampleRate, random)
        XCTAssertEqual(config.defaultPrivacyLevel, .mask)
        XCTAssertNil(config.customEndpoint)
    }
}
