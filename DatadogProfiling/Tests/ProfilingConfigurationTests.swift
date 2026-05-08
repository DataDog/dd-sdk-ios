/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import DatadogProfiling

final class ProfilingConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        // When
        let endpoint: URL = .mockRandom()
        let config = Profiling.Configuration(customEndpoint: endpoint)

        // Then
        XCTAssertEqual(config.customEndpoint, endpoint)
        XCTAssertEqual(config.applicationLaunchSampleRate, 5)
        XCTAssertEqual(config.continuousSampleRate, 5)
        XCTAssertFalse(config.featureFlags[.cpuTimeSamples])
    }

    func testConfigurationWithCPUTimingFeatureFlag() {
        // When
        let config = Profiling.Configuration(
            featureFlags: [
                .cpuTimeSamples: true
            ]
        )

        // Then
        XCTAssertTrue(config.featureFlags[.cpuTimeSamples])
    }
}

#endif
