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
        XCTAssertNil(config.mapper)
        XCTAssertEqual(config.sampleRate, 100)
        XCTAssertNil(config.customEndpoint)
        XCTAssertTrue(config.bundle === Bundle.main)
        XCTAssertTrue(config.processInfo === ProcessInfo.processInfo)
    }

    func testConfigurationOverrides() throws {
        // Given
        let sampleRate: Float = .random(in: 0...100)
        let customEndpoint: URL = .mockRandom()
        let bundleIdentifier: String = .mockRandom()
        
        let core = SingleFeatureCoreMock<LogsFeature>()

        // When
        Logs.enable(
            with: Logs.Configuration(
                eventMapper: { $0 },
                sampleRate: sampleRate,
                customEndpoint: customEndpoint,
                bundle: .mockWith(bundleIdentifier: bundleIdentifier)
            ),
            in: core
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        let requestBuilder = try XCTUnwrap(logs.requestBuilder as? RequestBuilder)
        XCTAssertNotNil(logs.logEventMapper)
        XCTAssertEqual(logs.applicationBundleIdentifier, bundleIdentifier)
        XCTAssertEqual(logs.sampler.samplingRate, sampleRate)
        XCTAssertEqual(requestBuilder.customIntakeURL, customEndpoint)
    }

    func testConfigurationInternalOverrides() throws {
        struct LogEventMapperMock: LogEventMapper {
            func map(event: DatadogLogs.LogEvent, callback: @escaping (DatadogLogs.LogEvent) -> Void) {
                callback(event)
            }
        }

        // Given
        let eventMapper = LogEventMapperMock()
        var config = Logs.Configuration()

        // When
        config._internal_mutation {
            $0.setLogEventMapper(eventMapper)
        }


        // Then
        XCTAssertTrue(config.mapper is LogEventMapperMock)
    }

    func testConfiguration_withDebug_itDisableSampling() throws {
        //Given
        let core = SingleFeatureCoreMock<LogsFeature>()

        var config = Logs.Configuration(sampleRate: 0)
        config.processInfo = ProcessInfoMock(arguments: [LaunchArguments.Debug])

        // When
        Logs.enable(with: config, in: core)

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        XCTAssertEqual(logs.sampler.samplingRate, 100)
    }
}
