/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension Datadog.Configuration.DatadogEndpoint: EquatableInTests {}
extension Datadog.Configuration.LogsEndpoint: EquatableInTests {}
extension Datadog.Configuration.TracesEndpoint: EquatableInTests {}
extension Datadog.Configuration.RUMEndpoint: EquatableInTests {}

class DatadogConfigurationBuilderTests: XCTestCase {
    func testDefaultBuilder() {
        let configuration = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
            .build()

        let rumConfiguration = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
            .build()

        XCTAssertFalse(configuration.rumEnabled)
        XCTAssertTrue(rumConfiguration.rumEnabled)

        XCTAssertNil(configuration.rumApplicationID)
        XCTAssertEqual(rumConfiguration.rumApplicationID, "rum-app-id")

        [configuration, rumConfiguration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertTrue(configuration.loggingEnabled)
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertNil(configuration.crashReportingPlugin)
            XCTAssertNil(configuration.datadogEndpoint)
            XCTAssertNil(configuration.customLogsEndpoint)
            XCTAssertNil(configuration.customTracesEndpoint)
            XCTAssertNil(configuration.customRUMEndpoint)
            XCTAssertEqual(configuration.logsEndpoint, .us)
            XCTAssertEqual(configuration.tracesEndpoint, .us)
            XCTAssertEqual(configuration.rumEndpoint, .us)
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertNil(configuration.spanEventMapper)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
            XCTAssertNil(configuration.rumUIKitViewsPredicate)
            XCTAssertFalse(configuration.rumUIKitActionsTrackingEnabled)
            XCTAssertNil(configuration.rumViewEventMapper)
            XCTAssertNil(configuration.rumResourceEventMapper)
            XCTAssertNil(configuration.rumActionEventMapper)
            XCTAssertNil(configuration.rumErrorEventMapper)
            XCTAssertNil(configuration.rumResourceAttributesProvider)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
        }
    }

    func testCustomizedBuilder() {
        let mockSpanEvent: SpanEvent = .mockAny()
        let mockRUMViewEvent: RUMViewEvent = .mockRandom()
        let mockRUMErrorEvent: RUMErrorEvent = .mockRandom()
        let mockRUMResourceEvent: RUMResourceEvent = .mockRandom()
        let mockRUMActionEvent: RUMActionEvent = .mockRandom()
        let mockCrashReportingPlugin = CrashReportingPluginMock()

        func customized(_ builder: Datadog.Configuration.Builder) -> Datadog.Configuration.Builder {
            _ = builder
                .set(serviceName: "service-name")
                .enableLogging(false)
                .enableTracing(false)
                .enableRUM(false)
                .enableCrashReporting(using: mockCrashReportingPlugin)
                .set(endpoint: .eu)
                .set(customLogsEndpoint: URL(string: "https://api.custom.logs/")!)
                .set(customTracesEndpoint: URL(string: "https://api.custom.traces/")!)
                .set(customRUMEndpoint: URL(string: "https://api.custom.rum/")!)
                .set(rumSessionsSamplingRate: 42.5)
                .setSpanEventMapper { _ in mockSpanEvent }
                .trackURLSession(firstPartyHosts: ["example.com"])
                .trackUIKitRUMViews(using: UIKitRUMViewsPredicateMock())
                .trackUIKitActions(false)
                .setRUMViewEventMapper { _ in mockRUMViewEvent }
                .setRUMErrorEventMapper { _ in mockRUMErrorEvent }
                .setRUMResourceEventMapper { _ in mockRUMResourceEvent }
                .setRUMActionEventMapper { _ in mockRUMActionEvent }
                .setRUMResourceAttributesProvider { _, _, _, _ in ["foo": "bar"] }
                .set(batchSize: .small)
                .set(uploadFrequency: .frequent)
                .set(additionalConfiguration: ["foo": 42, "bar": "something"])

            return builder
        }

        let defaultBuilder = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
        let defaultRUMBuilder = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
        let rumBuilderWithDefaultValues = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
            .trackUIKitRUMViews()
            .trackUIKitActions()

        let configuration = customized(defaultBuilder).build()
        let rumConfiguration = customized(defaultRUMBuilder).build()
        let rumConfigurationWithDefaultValues = rumBuilderWithDefaultValues.build()

        XCTAssertNil(configuration.rumApplicationID)
        XCTAssertEqual(rumConfiguration.rumApplicationID, "rum-app-id")

        [configuration, rumConfiguration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertEqual(configuration.serviceName, "service-name")
            XCTAssertFalse(configuration.loggingEnabled)
            XCTAssertFalse(configuration.tracingEnabled)
            XCTAssertFalse(configuration.rumEnabled)
            XCTAssertTrue(configuration.crashReportingPlugin === mockCrashReportingPlugin)
            XCTAssertEqual(configuration.datadogEndpoint, .eu)
            XCTAssertEqual(configuration.customLogsEndpoint, URL(string: "https://api.custom.logs/")!)
            XCTAssertEqual(configuration.customTracesEndpoint, URL(string: "https://api.custom.traces/")!)
            XCTAssertEqual(configuration.customRUMEndpoint, URL(string: "https://api.custom.rum/")!)
            XCTAssertEqual(configuration.firstPartyHosts, ["example.com"])
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 42.5)
            XCTAssertTrue(configuration.rumUIKitViewsPredicate is UIKitRUMViewsPredicateMock)
            XCTAssertEqual(configuration.spanEventMapper?(.mockRandom()), mockSpanEvent)
            XCTAssertFalse(configuration.rumUIKitActionsTrackingEnabled)
            XCTAssertEqual(configuration.rumViewEventMapper?(.mockRandom()), mockRUMViewEvent)
            XCTAssertEqual(configuration.rumResourceEventMapper?(.mockRandom()), mockRUMResourceEvent)
            XCTAssertEqual(configuration.rumActionEventMapper?(.mockRandom()), mockRUMActionEvent)
            XCTAssertEqual(configuration.rumErrorEventMapper?(.mockRandom()), mockRUMErrorEvent)
            XCTAssertEqual(configuration.rumResourceAttributesProvider?(.mockAny(), nil, nil, nil) as? [String: String], ["foo": "bar"])
            XCTAssertEqual(configuration.batchSize, .small)
            XCTAssertEqual(configuration.uploadFrequency, .frequent)
            XCTAssertEqual(configuration.additionalConfiguration["foo"] as? Int, 42)
            XCTAssertEqual(configuration.additionalConfiguration["bar"] as? String, "something")
        }

        XCTAssertTrue(rumConfigurationWithDefaultValues.rumUIKitViewsPredicate is DefaultUIKitRUMViewsPredicate)
        XCTAssertTrue(rumConfigurationWithDefaultValues.rumUIKitActionsTrackingEnabled)
    }

    func testDeprecatedAPIs() {
        let builder = Datadog.Configuration.builderUsing(clientToken: "abc-123", environment: "tests")
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(tracedHosts: ["example.com"])
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(logsEndpoint: .eu)
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(tracesEndpoint: .eu)
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(rumEndpoint: .eu)

        let configuration = builder.build()

        XCTAssertEqual(configuration.firstPartyHosts, ["example.com"])
        XCTAssertEqual(configuration.logsEndpoint, .eu)
        XCTAssertEqual(configuration.tracesEndpoint, .eu)
        XCTAssertEqual(configuration.rumEndpoint, .eu)
    }
}

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol ConfigurationBuilderDeprecatedAPIs {
    func set(tracedHosts: Set<String>) -> Datadog.Configuration.Builder
    func set(logsEndpoint: Datadog.Configuration.LogsEndpoint) -> Datadog.Configuration.Builder
    func set(tracesEndpoint: Datadog.Configuration.TracesEndpoint) -> Datadog.Configuration.Builder
    func set(rumEndpoint: Datadog.Configuration.RUMEndpoint) -> Datadog.Configuration.Builder
}
extension Datadog.Configuration.Builder: ConfigurationBuilderDeprecatedAPIs {}
