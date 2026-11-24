/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

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
        XCTAssertEqual(config.cpuSampleRate, 5)
        XCTAssertEqual(config.memorySampleRate, 0)
    }

    func testCustomConfiguration() {
        let endpoint: URL = .mockRandom()
        let configuration = Profiling.Configuration(
            customEndpoint: endpoint,
            applicationLaunchSampleRate: 12.5,
            cpuSampleRate: 37.5,
            memorySampleRate: 62.5
        )

        XCTAssertEqual(configuration.customEndpoint, endpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, 12.5)
        XCTAssertEqual(configuration.cpuSampleRate, 37.5)
        XCTAssertEqual(configuration.memorySampleRate, 62.5)
    }

    @available(*, deprecated)
    func testLegacyInitializerReferencePreservesConfiguration() {
        let makeConfiguration: (URL?, Float, Float) -> Profiling.Configuration = Profiling.Configuration.init
        let endpoint: URL = .mockRandom()

        let configuration = makeConfiguration(endpoint, 12.5, 37.5)

        XCTAssertEqual(configuration.customEndpoint, endpoint)
        XCTAssertEqual(configuration.applicationLaunchSampleRate, 12.5)
        XCTAssertEqual(configuration.cpuSampleRate, 37.5)
        XCTAssertEqual(configuration.memorySampleRate, 0)
    }

    @available(*, deprecated)
    func testLegacyContinuousSampleRateForwardsToCPUSampleRate() {
        var configuration = Profiling.Configuration(cpuSampleRate: 25, memorySampleRate: 50)
        XCTAssertEqual(configuration.continuousSampleRate, 25)

        configuration.continuousSampleRate = 75
        XCTAssertEqual(configuration.cpuSampleRate, 75)

        configuration.cpuSampleRate = 10
        XCTAssertEqual(configuration.continuousSampleRate, 10)
        XCTAssertEqual(configuration.memorySampleRate, 50)
    }
}

#endif
