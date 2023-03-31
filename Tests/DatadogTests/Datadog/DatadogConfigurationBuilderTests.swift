/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

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
            XCTAssertEqual(configuration.logsEndpoint, .us1)
            XCTAssertEqual(configuration.tracesEndpoint, .us1)
            XCTAssertEqual(configuration.rumEndpoint, .us1)
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertNil(configuration.logEventMapper)
            XCTAssertNil(configuration.spanEventMapper)
            XCTAssertEqual(configuration.loggingSamplingRate, 100.0)
            XCTAssertEqual(configuration.tracingSamplingRate, 20.0)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
            XCTAssertNil(configuration.rumSessionsListener)
            XCTAssertNil(configuration.rumUIKitViewsPredicate)
            XCTAssertNil(configuration.rumUIKitUserActionsPredicate)
            XCTAssertNil(configuration.rumLongTaskDurationThreshold)
            XCTAssertNil(configuration.rumViewEventMapper)
            XCTAssertNil(configuration.rumResourceEventMapper)
            XCTAssertNil(configuration.rumActionEventMapper)
            XCTAssertNil(configuration.rumErrorEventMapper)
            XCTAssertNil(configuration.rumLongTaskEventMapper)
            XCTAssertFalse(configuration.rumBackgroundEventTrackingEnabled)
            XCTAssertTrue(configuration.rumFrustrationSignalsTrackingEnabled)
            XCTAssertNil(configuration.rumResourceAttributesProvider)
            XCTAssertEqual(configuration.mobileVitalsFrequency, .average)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
            XCTAssertNil(configuration.encryption)
            XCTAssertNil(configuration.serverDateProvider)
        }
    }

    func testCustomizedBuilder() {
        let mockLogEvent: LogEvent = .mockAny()
        let mockSpanEvent: SpanEvent = .mockAny()
        let mockRUMViewEvent: RUMViewEvent = .mockRandom()
        let mockRUMErrorEvent: RUMErrorEvent = .mockRandom()
        let mockRUMResourceEvent: RUMResourceEvent = .mockRandom()
        let mockRUMActionEvent: RUMActionEvent = .mockRandom()
        let mockRUMLongTaskEvent: RUMLongTaskEvent = .mockRandom()
        let mockCrashReportingPlugin = CrashReportingPluginMock()

        func customized(_ builder: Datadog.Configuration.Builder) -> Datadog.Configuration.Builder {
            _ = builder
                .set(serviceName: "service-name")
                .enableLogging(false)
                .enableTracing(false)
                .enableRUM(false)
                .enableCrashReporting(using: mockCrashReportingPlugin)
                .set(endpoint: .eu1)
                .set(customLogsEndpoint: URL(string: "https://api.custom.logs/")!)
                .set(customTracesEndpoint: URL(string: "https://api.custom.traces/")!)
                .set(customRUMEndpoint: URL(string: "https://api.custom.rum/")!)
                .set(rumSessionsSamplingRate: 42.5)
                .onRUMSessionStart { _, _ in }
                .setLogEventMapper { _ in mockLogEvent }
                .setSpanEventMapper { _ in mockSpanEvent }
                .set(loggingSamplingRate: 66)
                .set(tracingSamplingRate: 75)
                .trackURLSession(firstPartyHosts: ["example.com"])
                .trackURLSession(firstPartyHostsWithHeaderTypes: ["example2.com": [.b3]])
                .trackUIKitRUMViews(using: UIKitRUMViewsPredicateMock())
                .trackUIKitRUMActions(using: UIKitRUMUserActionsPredicateMock())
                .trackRUMLongTasks(threshold: 100.0)
                .trackBackgroundEvents(false)
                .trackFrustrations(false)
                .setRUMViewEventMapper { _ in mockRUMViewEvent }
                .setRUMErrorEventMapper { _ in mockRUMErrorEvent }
                .setRUMResourceEventMapper { _ in mockRUMResourceEvent }
                .setRUMActionEventMapper { _ in mockRUMActionEvent }
                .setRUMLongTaskEventMapper { _ in mockRUMLongTaskEvent }
                .setRUMResourceAttributesProvider { _, _, _, _ in ["foo": "bar"] }
                .set(mobileVitalsFrequency: .frequent)
                .set(batchSize: .small)
                .set(uploadFrequency: .frequent)
                .set(additionalConfiguration: ["foo": 42, "bar": "something"])
                .set(proxyConfiguration: [
                    kCFNetworkProxiesHTTPEnable: true,
                    kCFNetworkProxiesHTTPPort: 123,
                    kCFNetworkProxiesHTTPProxy: "www.example.com",
                    kCFProxyUsernameKey: "proxyuser",
                    kCFProxyPasswordKey: "proxypass",
                ])
                .set(encryption: DataEncryptionMock())
                .set(serverDateProvider: ServerDateProviderMock())

            return builder
        }

        let defaultBuilder = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
        let defaultRUMBuilder = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
        let rumBuilderWithDefaultValues = Datadog.Configuration
            .builderUsing(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
            .trackUIKitRUMViews()
            .trackUIKitRUMActions()
            .trackBackgroundEvents()

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
            XCTAssertEqual(configuration.datadogEndpoint, .eu1)
            XCTAssertEqual(configuration.customLogsEndpoint, URL(string: "https://api.custom.logs/")!)
            XCTAssertEqual(configuration.customTracesEndpoint, URL(string: "https://api.custom.traces/")!)
            XCTAssertEqual(configuration.customRUMEndpoint, URL(string: "https://api.custom.rum/")!)
            XCTAssertEqual(configuration.firstPartyHosts, .init(["example.com": [.datadog], "example2.com": [.b3]]))
            XCTAssertEqual(configuration.loggingSamplingRate, 66)
            XCTAssertEqual(configuration.tracingSamplingRate, 75)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 42.5)
            XCTAssertNotNil(configuration.rumSessionsListener)
            XCTAssertEqual(configuration.rumTelemetrySamplingRate, 20)
            XCTAssertTrue(configuration.rumUIKitViewsPredicate is UIKitRUMViewsPredicateMock)
            XCTAssertTrue(configuration.rumUIKitUserActionsPredicate is UIKitRUMUserActionsPredicateMock)
            XCTAssertEqual(configuration.rumLongTaskDurationThreshold, 100.0)
            DDAssertReflectionEqual(configuration.spanEventMapper?(.mockRandom()), mockSpanEvent)
            DDAssertReflectionEqual(configuration.rumViewEventMapper?(.mockRandom()), mockRUMViewEvent)
            DDAssertReflectionEqual(configuration.rumResourceEventMapper?(.mockRandom()), mockRUMResourceEvent)
            DDAssertReflectionEqual(configuration.rumActionEventMapper?(.mockRandom()), mockRUMActionEvent)
            DDAssertReflectionEqual(configuration.rumErrorEventMapper?(.mockRandom()), mockRUMErrorEvent)
            DDAssertReflectionEqual(configuration.rumLongTaskEventMapper?(.mockRandom()), mockRUMLongTaskEvent)
            XCTAssertEqual(configuration.rumResourceAttributesProvider?(.mockAny(), nil, nil, nil) as? [String: String], ["foo": "bar"])
            XCTAssertFalse(configuration.rumBackgroundEventTrackingEnabled)
            XCTAssertFalse(configuration.rumFrustrationSignalsTrackingEnabled)
            XCTAssertEqual(configuration.mobileVitalsFrequency, .frequent)
            XCTAssertEqual(configuration.batchSize, .small)
            XCTAssertEqual(configuration.uploadFrequency, .frequent)
            XCTAssertEqual(configuration.additionalConfiguration["foo"] as? Int, 42)
            XCTAssertEqual(configuration.additionalConfiguration["bar"] as? String, "something")
            XCTAssertEqual(configuration.proxyConfiguration?[kCFNetworkProxiesHTTPEnable] as? Bool, true)
            XCTAssertEqual(configuration.proxyConfiguration?[kCFNetworkProxiesHTTPPort] as? Int, 123)
            XCTAssertEqual(configuration.proxyConfiguration?[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
            XCTAssertEqual(configuration.proxyConfiguration?[kCFProxyUsernameKey] as? String, "proxyuser")
            XCTAssertEqual(configuration.proxyConfiguration?[kCFProxyPasswordKey] as? String, "proxypass")
            XCTAssertTrue(configuration.encryption is DataEncryptionMock)
            XCTAssertTrue(configuration.serverDateProvider is ServerDateProviderMock)

            // Aync mapper:
            configuration.logEventMapper?.map(event: .mockRandom()) { event in
                DDAssertReflectionEqual(event, mockLogEvent)
            }
        }

        XCTAssertTrue(rumConfigurationWithDefaultValues.rumUIKitViewsPredicate is DefaultUIKitRUMViewsPredicate)
        XCTAssertTrue(rumConfigurationWithDefaultValues.rumUIKitUserActionsPredicate is DefaultUIKitRUMUserActionsPredicate)
        XCTAssertTrue(rumConfigurationWithDefaultValues.rumBackgroundEventTrackingEnabled)
    }

    func testDeprecatedAPIs() {
        let builder = Datadog.Configuration.builderUsing(clientToken: "abc-123", environment: "tests")
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(tracedHosts: ["example.com"])
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(logsEndpoint: .eu1)
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(tracesEndpoint: .eu1)
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(rumEndpoint: .eu1)
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).trackUIKitActions(true)

        let configuration = builder.build()

        XCTAssertEqual(configuration.firstPartyHosts, .init(["example.com": [.datadog]]))
        XCTAssertEqual(configuration.logsEndpoint, .eu1)
        XCTAssertEqual(configuration.tracesEndpoint, .eu1)
        XCTAssertEqual(configuration.rumEndpoint, .eu1)
        XCTAssertTrue(configuration.rumUIKitUserActionsPredicate is DefaultUIKitRUMUserActionsPredicate)
    }
}

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol ConfigurationBuilderDeprecatedAPIs {
    func set(tracedHosts: Set<String>) -> Datadog.Configuration.Builder
    func set(logsEndpoint: Datadog.Configuration.LogsEndpoint) -> Datadog.Configuration.Builder
    func set(tracesEndpoint: Datadog.Configuration.TracesEndpoint) -> Datadog.Configuration.Builder
    func set(rumEndpoint: Datadog.Configuration.RUMEndpoint) -> Datadog.Configuration.Builder
    func trackUIKitActions(_ enabled: Bool) -> Datadog.Configuration.Builder
}
extension Datadog.Configuration.Builder: ConfigurationBuilderDeprecatedAPIs {}
