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
    func testDefaultConfiguration() {
        let configuration = objc_ProfilingConfiguration()

        XCTAssertNil(configuration.customEndpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, 5)
        XCTAssertEqual(configuration.cpuSampleRate, 5)
        XCTAssertEqual(configuration.memorySampleRate, 0)
        XCTAssertEqual(configuration.configuration.memorySampleRate, 0)

        let cpuOnlyConfiguration = objc_ProfilingConfiguration(cpuSampleRate: 25)
        XCTAssertEqual(cpuOnlyConfiguration.cpuSampleRate, 25)
        XCTAssertEqual(cpuOnlyConfiguration.memorySampleRate, 0)
    }

    func testCustomConfiguration() {
        let customEndpoint: URL = .mockRandom()
        let applicationLaunchSampleRate: Float = .mockRandom(min: 0, max: 100)
        let cpuSampleRate: Float = .mockRandom(min: 0, max: 100)
        let memorySampleRate: Float = .mockRandom(min: 0, max: 100)
        let configuration = objc_ProfilingConfiguration(
            customEndpoint: customEndpoint,
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            cpuSampleRate: cpuSampleRate,
            memorySampleRate: memorySampleRate
        )

        XCTAssertEqual(configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.cpuSampleRate, cpuSampleRate)
        XCTAssertEqual(configuration.configuration.cpuSampleRate, cpuSampleRate)
        XCTAssertEqual(configuration.memorySampleRate, memorySampleRate)
        XCTAssertEqual(configuration.configuration.memorySampleRate, memorySampleRate)
    }

    func testMutatingConfigurationForwardsToSwift() {
        let configuration = objc_ProfilingConfiguration()
        let customEndpoint: URL = .mockRandom()
        let applicationLaunchSampleRate: Float = .mockRandom(min: 0, max: 100)
        let cpuSampleRate: Float = .mockRandom(min: 0, max: 100)
        let memorySampleRate: Float = .mockRandom(min: 0, max: 100)

        configuration.customEndpoint = customEndpoint
        configuration.applicationLaunchSampleRate = applicationLaunchSampleRate
        configuration.cpuSampleRate = cpuSampleRate
        configuration.memorySampleRate = memorySampleRate

        XCTAssertEqual(configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.configuration.customEndpoint, customEndpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.configuration.applicationLaunchSampleRate, applicationLaunchSampleRate)
        XCTAssertEqual(configuration.cpuSampleRate, cpuSampleRate)
        XCTAssertEqual(configuration.configuration.cpuSampleRate, cpuSampleRate)
        XCTAssertEqual(configuration.memorySampleRate, memorySampleRate)
        XCTAssertEqual(configuration.configuration.memorySampleRate, memorySampleRate)

        configuration.configuration.memorySampleRate = 0
        XCTAssertEqual(configuration.memorySampleRate, 0)

        configuration.customEndpoint = nil
        XCTAssertNil(configuration.customEndpoint)
        XCTAssertNil(configuration.configuration.customEndpoint)
    }

    @available(*, deprecated)
    func testLegacyInitializerReferencePreservesConfiguration() {
        let makeConfiguration: (URL?, Float, Float) -> objc_ProfilingConfiguration = objc_ProfilingConfiguration.init
        let endpoint: URL = .mockRandom()

        let configuration = makeConfiguration(endpoint, 12.5, 37.5)

        XCTAssertEqual(configuration.customEndpoint, endpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, 12.5)
        XCTAssertEqual(configuration.cpuSampleRate, 37.5)
        XCTAssertEqual(configuration.memorySampleRate, 0)
    }

    @available(*, deprecated)
    func testLegacyContinuousSampleRateForwardsToSwiftCPUSampleRate() {
        let configuration = objc_ProfilingConfiguration(cpuSampleRate: 25, memorySampleRate: 50)
        XCTAssertEqual(configuration.continuousSampleRate, 25)

        configuration.continuousSampleRate = 75
        XCTAssertEqual(configuration.cpuSampleRate, 75)
        XCTAssertEqual(configuration.configuration.cpuSampleRate, 75)

        configuration.cpuSampleRate = 10
        XCTAssertEqual(configuration.continuousSampleRate, 10)
        XCTAssertEqual(configuration.memorySampleRate, 50)
    }
}

#endif
