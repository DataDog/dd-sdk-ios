/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogLogs

class LogsTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let config = Logs.Configuration()

        // Then
        XCTAssertNil(config.eventMapper)
        XCTAssertEqual(config.samplingRate, 100)
        XCTAssertNil(config.customIntakeURL)
        XCTAssertTrue(config.bundle === Bundle.main)
        XCTAssertTrue(config.processInfo === ProcessInfo.processInfo)
    }

    func testConfigurationOverrides() throws {
        // Given
        let samplingRate: Float = .random(in: 0...100)
        let customIntakeURL: URL = .mockRandom()
        let bundleIdentifier: String = .mockRandom()
        
        let core = SingleFeatureCoreMock<LogsFeature>()

        // When
        Logs.enable(
            with: Logs.Configuration(
                eventMapper: { $0 },
                samplingRate: samplingRate,
                customIntakeURL: customIntakeURL,
                bundle: .mockWith(bundleIdentifier: bundleIdentifier)
            ),
            in: core
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        let requestBuilder = try XCTUnwrap(logs.requestBuilder as? RequestBuilder)
        XCTAssertNotNil(logs.logEventMapper)
        XCTAssertEqual(logs.applicationBundleIdentifier, bundleIdentifier)
        XCTAssertEqual(logs.sampler.samplingRate, samplingRate)
        XCTAssertEqual(requestBuilder.customIntakeURL, customIntakeURL)
    }

    func testConfigurationInternalOverrides() throws {
        struct LogEventMapperMock: LogEventMapper {
            func map(event: DatadogLogs.LogEvent, callback: @escaping (DatadogLogs.LogEvent) -> Void) {
                callback(event)
            }
        }

        // Given
        let eventMapper = LogEventMapperMock()
        let config = Logs.Configuration()

        // When
        config._internal.setLogEventMapper(eventMapper)

        // Then
        XCTAssertTrue(config.eventMapper is LogEventMapperMock)
    }

    func testConfiguration_withDebug_itDisableSampling() throws {
        //Given
        let core = SingleFeatureCoreMock<LogsFeature>()

        // When
        Logs.enable(
            with: Logs.Configuration(
                samplingRate: 0,
                processInfo: ProcessInfoMock(arguments: [LaunchArguments.Debug])
            ),
            in: core
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        XCTAssertEqual(logs.sampler.samplingRate, 100)
    }
}
