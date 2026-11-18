/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import TestUtilities
@_spi(objc)
@testable import DatadogProfiling

final class DDProfilingConfigurationTests: XCTestCase {
    func testCustomConfiguration() {
        let customEndpoint: URL = .mockRandom()
        let applicationLaunchSampleRate: Float = .mockRandom(min: 0, max: 100)
        let continuousSampleRate: Float = .mockRandom(min: 0, max: 100)
        let configuration = objc_ProfilingConfiguration(
            customEndpoint: customEndpoint,
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            continuousSampleRate: continuousSampleRate
        )

        XCTAssertEqual(configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.continuousSampleRate, continuousSampleRate)
        XCTAssertEqual(configuration.configuration.continuousSampleRate, continuousSampleRate)
    }

    func testMutatingConfigurationForwardsToSwift() {
        let configuration = objc_ProfilingConfiguration()
        let customEndpoint: URL = .mockRandom()
        let applicationLaunchSampleRate: Float = .mockRandom(min: 0, max: 100)
        let continuousSampleRate: Float = .mockRandom(min: 0, max: 100)

        configuration.customEndpoint = customEndpoint
        configuration.applicationLaunchSampleRate = applicationLaunchSampleRate
        configuration.continuousSampleRate = continuousSampleRate

        XCTAssertEqual(configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.continuousSampleRate, continuousSampleRate)
        XCTAssertEqual(configuration.configuration.continuousSampleRate, continuousSampleRate)

        configuration.customEndpoint = nil
        XCTAssertNil(configuration.customEndpoint)
        XCTAssertNil(configuration.configuration.customEndpoint)
    }
}

#endif
