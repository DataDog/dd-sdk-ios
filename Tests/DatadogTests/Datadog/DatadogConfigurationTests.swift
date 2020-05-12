/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DatadogConfigurationTests: XCTestCase {
    private typealias Configuration = Datadog.Configuration

    func testDefaultConfiguration() {
        let defaultConfiguration = Configuration.builderUsing(clientToken: "abcd", environment: "tests").build()
        XCTAssertEqual(defaultConfiguration.clientToken, "abcd")
        XCTAssertEqual(defaultConfiguration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")
        XCTAssertEqual(defaultConfiguration.environment, "tests")
        XCTAssertNil(defaultConfiguration.serviceName)
    }

    func testCustomConfiguration() {
        let configuration = Configuration.builderUsing(clientToken: "abcd", environment: "tests")
            .set(serviceName: "service-name")
            .build()
        XCTAssertEqual(configuration.clientToken, "abcd")
        XCTAssertEqual(configuration.environment, "tests")
        XCTAssertEqual(configuration.serviceName, "service-name")
    }

    // MARK: - Log endpoints

    func testLoggingEndpoints() {
        var configuration = Configuration.builderUsing(clientToken: .mockAny(), environment: .mockAny())
            .set(logsEndpoint: .us)
            .build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")

        configuration = Configuration.builderUsing(clientToken: .mockAny(), environment: .mockAny())
            .set(logsEndpoint: .eu)
            .build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://mobile-http-intake.logs.datadoghq.eu/v1/input/")

        configuration = Configuration.builderUsing(clientToken: .mockAny(), environment: .mockAny())
            .set(logsEndpoint: .custom(url: "https://api.example.com/v1/logs/"))
            .build()
        XCTAssertEqual(configuration.logsEndpoint.url, "https://api.example.com/v1/logs/")
    }
}

class DatadogValidConfigurationTests: XCTestCase {
    private typealias Configuration = Datadog.ValidConfiguration

    // MARK: - Successfull validation

    func testApplicationName() throws {
        // it equals `.bundleName`
        var configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleName: "app-name")
        )
        XCTAssertEqual(configuration.applicationName, "app-name")

        // it fallbacks to `.bundleType` when `.bundleName` is `nil`
        configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleType: .iOSApp, bundleName: nil)
        )
        XCTAssertEqual(configuration.applicationName, "iOSApp")

        // it fallbacks to `.bundleType` when `.bundleName` is `nil`
        configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleType: .iOSAppExtension, bundleName: nil)
        )
        XCTAssertEqual(configuration.applicationName, "iOSAppExtension")
    }

    func testApplicationVersion() throws {
        // it equals `.bundleVersion`
        var configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleVersion: "1.2.3")
        )
        XCTAssertEqual(configuration.applicationVersion, "1.2.3")

        // it fallbacks to "0.0.0" when `.bundleVersion` is `nil`
        configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleVersion: nil)
        )
        XCTAssertEqual(configuration.applicationVersion, "0.0.0")
    }

    func testApplicationBundleIdentifier() throws {
        // it equals `.bundleIdentifier`
        var configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.applicationBundleIdentifier, "com.datadoghq.tests")

        // it fallbacks to "unknown" if `.bundleIdentifier` is `nil`
        configuration = try Configuration(
            configuration: .mockAny(),
            appContext: .mockWith(bundleIdentifier: nil)
        )
        XCTAssertEqual(configuration.applicationBundleIdentifier, "unknown")
    }

    func testServiceName() throws {
        // it equals `Datadog.Configuration.serviceName`
        var configuration = try Configuration(
            configuration: .mockWith(serviceName: "service-name"),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.serviceName, "service-name")

        // it fallbacks to `.bundleIdentifier` when `Datadog.Configuration.serviceName` is not set
        configuration = try Configuration(
            configuration: .mockWith(serviceName: nil),
            appContext: .mockWith(bundleIdentifier: "com.datadoghq.tests")
        )
        XCTAssertEqual(configuration.serviceName, "com.datadoghq.tests")

        // it fallbacks to "ios" when `Datadog.Configuration.serviceName` is not set and `.bundleIdentifier` is `nil`
        configuration = try Configuration(
            configuration: .mockWith(serviceName: nil),
            appContext: .mockWith(bundleIdentifier: nil)
        )
        XCTAssertEqual(configuration.serviceName, "ios")
    }

    // MARK: - Validation

    func testEnvironmentValidation() throws {
        func verify(validEnvironmentName environment: String) throws {
            // it equals `Datadog.Configuration.environment`
            let configuration = try Configuration(
                configuration: .mockWith(environment: environment),
                appContext: .mockAny()
            )
            XCTAssertEqual(configuration.environment, environment)
        }
        func verify(invalidEnvironmentName environment: String) {
            XCTAssertThrowsError(try Configuration(configuration: .mockWith(environment: environment), appContext: .mockAny())) { error in
                XCTAssertEqual(
                    (error as? ProgrammerError)?.description,
                    "Datadog SDK usage error: `environment` contains illegal characters (only alphanumerics and `_` are allowed)"
                )
            }
        }

        try verify(validEnvironmentName: "staging_1")
        try verify(validEnvironmentName: "production")

        verify(invalidEnvironmentName: "")
        verify(invalidEnvironmentName: "*^@!&#")
        verify(invalidEnvironmentName: "abc def")
        verify(invalidEnvironmentName: "*^@!&#")
    }

    func testLogsUploadURLValidation() throws {
        func verify(clientToken: String, logsEndpoint: Datadog.Configuration.LogsEndpoint, expectedLogsUploadURL: URL) throws {
            // it equals `Datadog.Configuration.environment`
            let configuration = try Configuration(
                configuration: .mockWith(clientToken: clientToken, logsEndpoint: logsEndpoint),
                appContext: .mockAny()
            )
            XCTAssertEqual(configuration.logsUploadURLWithClientToken, expectedLogsUploadURL)
        }
        func verify(clientToken: String, logsEndpoint: Datadog.Configuration.LogsEndpoint, expectedError: String) {
            XCTAssertThrowsError(
                try Configuration(
                    configuration: .mockWith(clientToken: clientToken, logsEndpoint: logsEndpoint),
                    appContext: .mockAny()
                )
            ) { error in
                XCTAssertEqual((error as? ProgrammerError)?.description, expectedError)
            }
        }

        try verify(
            clientToken: "abc",
            logsEndpoint: .us,
            expectedLogsUploadURL: URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abc")!
        )
        try verify(
            clientToken: "abc",
            logsEndpoint: .eu,
            expectedLogsUploadURL: URL(string: "https://mobile-http-intake.logs.datadoghq.eu/v1/input/abc")!
        )
        try verify(
            clientToken: "abc",
            logsEndpoint: .custom(url: "http://example.com/api"),
            expectedLogsUploadURL: URL(string: "http://example.com/api/abc")!
        )
        verify(clientToken: "", logsEndpoint: .us, expectedError: "Datadog SDK usage error: `clientToken` cannot be empty.")
        verify(clientToken: "", logsEndpoint: .eu, expectedError: "Datadog SDK usage error: `clientToken` cannot be empty.")
        verify(
            clientToken: "",
            logsEndpoint: .custom(url: URL.mockAny().absoluteString),
            expectedError: "Datadog SDK usage error: `clientToken` cannot be empty."
        )
        verify(
            clientToken: "abc",
            logsEndpoint: .custom(url: ""),
            expectedError: "Datadog SDK usage error: The `url` in `.custom(url:)` must be a valid URL string."
        )
        verify(
            clientToken: "abc",
            logsEndpoint: .custom(url: "not a valid url string"),
            expectedError: "Datadog SDK usage error: The `url` in `.custom(url:)` must be a valid URL string."
        )
    }
}
