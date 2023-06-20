/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogLogs
@testable import DatadogRUM
@testable import Datadog

class DatadogConfigurationBuilderTests: XCTestCase {
    func testDefaultBuilder() {
        let configuration = Datadog.Configuration
            .builderUsing(clientToken: "abc-123", environment: "tests")
            .build()

        [configuration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertTrue(configuration.loggingEnabled)
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertEqual(configuration.datadogEndpoint, .us1)
            XCTAssertNil(configuration.customLogsEndpoint)
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertNil(configuration.logEventMapper)
            XCTAssertEqual(configuration.loggingSamplingRate, 100.0)
            XCTAssertEqual(configuration.tracingSamplingRate, 20.0)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
            XCTAssertNil(configuration.encryption)
            XCTAssertNil(configuration.serverDateProvider)
        }
    }

    func testCustomizedBuilder() {
        let mockLogEvent: LogEvent = .mockAny()

        func customized(_ builder: Datadog.Configuration.Builder) -> Datadog.Configuration.Builder {
            _ = builder
                .set(serviceName: "service-name")
                .enableLogging(false)
                .enableTracing(false)
                .set(endpoint: .eu1)
                .set(customLogsEndpoint: URL(string: "https://api.custom.logs/")!)
                .setLogEventMapper { _ in mockLogEvent }
                .set(loggingSamplingRate: 66)
                .set(tracingSamplingRate: 75)
                .trackURLSession(firstPartyHosts: ["example.com"])
                .trackURLSession(firstPartyHostsWithHeaderTypes: ["example2.com": [.b3]])
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

        let configuration = customized(defaultBuilder).build()

        [configuration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertEqual(configuration.serviceName, "service-name")
            XCTAssertFalse(configuration.loggingEnabled)
            XCTAssertFalse(configuration.tracingEnabled)
            XCTAssertEqual(configuration.datadogEndpoint, .eu1)
            XCTAssertEqual(configuration.customLogsEndpoint, URL(string: "https://api.custom.logs/")!)
            XCTAssertEqual(configuration.firstPartyHosts, .init(["example.com": [.datadog], "example2.com": [.b3]]))
            XCTAssertEqual(configuration.loggingSamplingRate, 66)
            XCTAssertEqual(configuration.tracingSamplingRate, 75)
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
    }

    func testDeprecatedAPIs() {
        let builder = Datadog.Configuration.builderUsing(clientToken: "abc-123", environment: "tests")
        _ = (builder as ConfigurationBuilderDeprecatedAPIs).set(tracedHosts: ["example.com"])

        let configuration = builder.build()

        XCTAssertEqual(configuration.firstPartyHosts, .init(["example.com": [.datadog]]))
    }
}

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol ConfigurationBuilderDeprecatedAPIs {
    func set(tracedHosts: Set<String>) -> Datadog.Configuration.Builder
}
extension Datadog.Configuration.Builder: ConfigurationBuilderDeprecatedAPIs {}
