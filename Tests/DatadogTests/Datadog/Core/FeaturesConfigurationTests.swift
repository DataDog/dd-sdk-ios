/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import Datadog

class FeaturesConfigurationTests: XCTestCase {
    // MARK: - Common Configuration

    func testApplicationName() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleName: "app-name")
        )
        XCTAssertEqual(configuration.common.applicationName, "app-name", "should use Bundle Name")

        configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleType: .iOSApp, bundleName: nil)
        )
        XCTAssertEqual(configuration.common.applicationName, "iOSApp", "should fallback to Bundle Type")
    }

    func testApplicationVersion() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleVersion: "1.2.3")
        )
        XCTAssertEqual(configuration.common.applicationVersion, "1.2.3", "should use Bundle version")

        configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleVersion: nil)
        )
        XCTAssertEqual(configuration.common.applicationVersion, "0.0.0", "should fallback to '0.0.0'")

        let randomVersion: String = .mockRandom()
        configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [CrossPlatformAttributes.version: randomVersion]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.applicationVersion, randomVersion, "Version can be customized through additional configuration")
    }

    func testApplicationVariant() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockAny()
        )
        XCTAssertNil(configuration.common.variant, "should not have a default variant")

        let randomVariant: String = .mockRandom()
        configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [CrossPlatformAttributes.variant: randomVariant]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.variant, randomVariant, "Variant can be customized through additional configuration")
    }

    func testApplicationBundleIdentifier() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.common.applicationBundleIdentifier, "com.datadoghq.tests", "should use Bundle identifier")

        configuration = try FeaturesConfiguration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleIdentifier: nil)
        )
        XCTAssertEqual(configuration.common.applicationBundleIdentifier, "unknown", "should fallback to 'unknown'")
    }

    func testServiceName() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockWith(serviceName: "service-name"),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.common.serviceName, "service-name", "should prioritize the value from `Datadog.Configuration`")

        configuration = try FeaturesConfiguration(
            configuration: .mockWith(serviceName: nil),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.common.serviceName, "com.datadoghq.tests", "should fallback to Bundle identifier")

        configuration = try FeaturesConfiguration(
            configuration: .mockWith(serviceName: nil),
            appContext: .mockWith(bundleIdentifier: nil)
        )
        XCTAssertEqual(configuration.common.serviceName, "ios", "should fallback to 'ios'")
    }

    func testEnvironment() throws {
        func verify(validEnvironmentName environment: String) throws {
            let configuration = try FeaturesConfiguration(
                configuration: .mockWith(environment: environment),
                appContext: .mockAny()
            )
            XCTAssertEqual(configuration.common.environment, environment, "should use the value from `Datadog.Configuration`")
        }
        func verify(invalidEnvironmentName environment: String) {
            XCTAssertThrowsError(try FeaturesConfiguration(configuration: .mockWith(environment: environment), appContext: .mockAny())) { error in
                XCTAssertEqual(
                    (error as? ProgrammerError)?.description,
                    "🔥 Datadog SDK usage error: `environment`: \(environment) contains illegal characters (only alphanumerics and `_` are allowed)"
                )
            }
        }

        try verify(validEnvironmentName: "staging_1")
        try verify(validEnvironmentName: "production")
        try verify(validEnvironmentName: "production:some")
        try verify(validEnvironmentName: "pro/d-uct.ion_")

        verify(invalidEnvironmentName: "")
        verify(invalidEnvironmentName: "*^@!&#")
        verify(invalidEnvironmentName: "abc def")
        verify(invalidEnvironmentName: "*^@!&#")
        verify(invalidEnvironmentName: "*^@!&#\nsome_env")
        verify(invalidEnvironmentName: String(repeating: "a", count: 197))
    }

    func testPerformancePreset() throws {
        try BatchSize.allCases
            .combined(with: UploadFrequency.allCases)
            .combined(with: BundleType.allCases)
            .map { ($0.0, $0.1, $1) }
            .forEach { batchSize, uploadFrequency, bundleType in
                let actualPerformancePreset = try FeaturesConfiguration(
                    configuration: .mockWith(batchSize: batchSize,uploadFrequency: uploadFrequency),
                    appContext: .mockWith(bundleType: bundleType)
                ).common.performance

                let expectedPerformancePreset = PerformancePreset(batchSize: batchSize, uploadFrequency: uploadFrequency, bundleType: bundleType)

                XCTAssertEqual(actualPerformancePreset, expectedPerformancePreset)
            }
    }

    func testSource() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [:]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.source, "ios", "Default `source` must be `ios`")

        let randomSource: String = .mockRandom()
        configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [CrossPlatformAttributes.ddsource: randomSource]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.source, randomSource, "Source can be customized through additional configuration")
    }

    func testSDKVersion() throws {
        var configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [:]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.sdkVersion, __sdkVersion, "Default `sdkVersion` must be equal to `__sdkVersion`")

        let randomSDKVersion: String = .mockRandom()
        configuration = try FeaturesConfiguration(
            configuration: .mockWith(additionalConfiguration: [CrossPlatformAttributes.sdkVersion: randomSDKVersion]),
            appContext: .mockAny()
        )
        XCTAssertEqual(configuration.common.sdkVersion, randomSDKVersion, "SDK version can be customized through additional configuration")
    }

    func testClientToken() throws {
        let clientToken: String = .mockRandom(among: .alphanumerics)
        let configuration = try createConfiguration(clientToken: clientToken)

        XCTAssertEqual(configuration.common.clientToken, clientToken)
    }

    func testCustomProxy() throws {
        let proxyConfiguration: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPPort: 123,
            kCFNetworkProxiesHTTPProxy: "www.example.com",
            kCFProxyUsernameKey: "proxyuser",
            kCFProxyPasswordKey: "proxypass",
        ]
        let configuration = try createConfiguration(proxyConfiguration: proxyConfiguration)

        XCTAssertEqual(configuration.common.proxyConfiguration?[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(configuration.common.proxyConfiguration?[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(configuration.common.proxyConfiguration?[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(configuration.common.proxyConfiguration?[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(configuration.common.proxyConfiguration?[kCFProxyPasswordKey] as? String, "proxypass")
    }

    // MARK: - Tracing Configuration Tests

    func testWhenTracingIsDisabled() throws {
        XCTAssertFalse(
            try FeaturesConfiguration(configuration: .mockWith(tracingEnabled: false), appContext: .mockAny()).tracingEnabled,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    // MARK: - URLSession Auto Instrumentation Configuration Tests

    func testURLSessionAutoInstrumentationConfiguration() throws {
        let randomDatadogEndpoint: DatadogSite = .mockRandom()

        let firstPartyHosts: FirstPartyHosts = .init([
            "example.com": [.datadog],
            "foo.eu": [.datadog]
        ])

        func createConfiguration(
            tracingEnabled: Bool,
            firstPartyHosts: FirstPartyHosts?
        ) throws -> FeaturesConfiguration {
            try FeaturesConfiguration(
                configuration: .mockWith(
                    tracingEnabled: tracingEnabled,
                    datadogEndpoint: randomDatadogEndpoint,
                    firstPartyHosts: firstPartyHosts
                ),
                appContext: .mockAny()
            )
        }

        // When `firstPartyHosts` are provided and both Tracing and RUM are enabled
        var configuration = try createConfiguration(
            tracingEnabled: true,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertTrue(configuration.tracingEnabled)

        // When `firstPartyHosts` are set and only Tracing is enabled
        configuration = try createConfiguration(
            tracingEnabled: true,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertTrue(configuration.tracingEnabled)

        // When `firstPartyHosts` are set and only RUM is enabled
        configuration = try createConfiguration(
            tracingEnabled: false,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertFalse(configuration.tracingEnabled)
    }

    // MARK: - Invalid Configurations

    func testWhenClientTokenIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try createConfiguration(clientToken: "")) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "🔥 Datadog SDK usage error: `clientToken` cannot be empty.")
        }
    }

    // MARK: - Helpers

    private func createConfiguration(
        clientToken: String = "abc",
        datadogEndpoint: DatadogSite = .us1,
        proxyConfiguration: [AnyHashable: Any]? = nil
    ) throws -> FeaturesConfiguration {
        return try FeaturesConfiguration(
            configuration: .mockWith(
                clientToken: clientToken,
                tracingEnabled: true,
                datadogEndpoint: datadogEndpoint,
                proxyConfiguration: proxyConfiguration
            ),
            appContext: .mockAny()
        )
    }
}
