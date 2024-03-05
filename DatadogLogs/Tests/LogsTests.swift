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
        XCTAssertNil(config.customEndpoint)
    }

    func testWhenNotEnabled_thenLogsIsEnabledIsFalse() {
        // When
        let core = FeatureRegistrationCoreMock()
        XCTAssertNil(core.get(feature: LogsFeature.self))

        // Then
        XCTAssertFalse(Logs._internal.isEnabled(in: core))
    }

    func testWhenEnabled_thenLogsIsEnabledIsTrue() {
        // When
        let core = FeatureRegistrationCoreMock()
        let config = Logs.Configuration()
        Logs.enable(with: config, in: core)

        // Then
        XCTAssertTrue(Logs._internal.isEnabled(in: core))
    }

    func testConfigurationOverrides() throws {
        // Given
        let customEndpoint: URL = .mockRandom()

        let core = SingleFeatureCoreMock<LogsFeature>()

        // When
        Logs.enable(
            with: Logs.Configuration(
                eventMapper: { $0 },
                customEndpoint: customEndpoint
            ),
            in: core
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        let requestBuilder = try XCTUnwrap(logs.requestBuilder as? RequestBuilder)
        XCTAssertNotNil(logs.logEventMapper)
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
        XCTAssertTrue(config._internalEventMapper is LogEventMapperMock)
    }

    func testLogsAddAttributeForwardedToFeature() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let config = Logs.Configuration()
        Logs.enable(with: config, in: core)

        // When
        let attributeKey: String = .mockRandom()
        let attributeValue: String = .mockRandom()
        Logs.addAttribute(forKey: attributeKey, value: attributeValue, in: core)

        // Then
        let feature = try XCTUnwrap(core.get(feature: LogsFeature.self))
        XCTAssertEqual(feature.getAttributes()[attributeKey] as? String, attributeValue)
    }

    func testLogsRemoveAttributeForwardedToFeature() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let config = Logs.Configuration()
        Logs.enable(with: config, in: core)
        let attributeKey: String = .mockRandom()
        let attributeValue: String = .mockRandom()
        Logs.addAttribute(forKey: attributeKey, value: attributeValue, in: core)

        // When
        Logs.removeAttribute(forKey: attributeKey, in: core)

        // Then
        let feature = try XCTUnwrap(core.get(feature: LogsFeature.self))
        XCTAssertNil(feature.getAttributes()[attributeKey])
    }
}
