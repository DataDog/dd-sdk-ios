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

        [configuration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertEqual(configuration.datadogEndpoint, .us1)
            XCTAssertNil(configuration.serviceName)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
            XCTAssertNil(configuration.encryption)
            XCTAssertNil(configuration.serverDateProvider)
        }
    }

    func testCustomizedBuilder() {
        func customized(_ builder: Datadog.Configuration.Builder) -> Datadog.Configuration.Builder {
            _ = builder
                .set(serviceName: "service-name")
                .set(endpoint: .eu1)
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
            XCTAssertEqual(configuration.datadogEndpoint, .eu1)
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
        }
    }
}
