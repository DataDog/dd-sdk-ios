/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension FeaturesConfiguration.Common: EquatableInTests {}

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

    func testPerformance() throws {
        let iOSAppConfiguration = try FeaturesConfiguration(
            configuration: .mockAny(), appContext: .mockWith(bundleType: .iOSApp)
        )
        XCTAssertEqual(iOSAppConfiguration.common.performance, .lowRuntimeImpact)

        let iOSAppExtensionConfiguration = try FeaturesConfiguration(
            configuration: .mockAny(), appContext: .mockWith(bundleType: .iOSAppExtension)
        )
        XCTAssertEqual(iOSAppExtensionConfiguration.common.performance, .instantDataDelivery)
    }

    // MARK: - Logging Configuration Tests

    func testLoggingConfiguration() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(loggingEnabled: false), appContext: .mockAny()).logging,
            "Feature configuration should not be available if the feature is disabled"
        )

        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", logsEndpoint: .us).logging?.uploadURLWithClientToken,
            URL(string: "https://mobile-http-intake.logs.datadoghq.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", logsEndpoint: .eu).logging?.uploadURLWithClientToken,
            URL(string: "https://mobile-http-intake.logs.datadoghq.eu/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", logsEndpoint: .gov).logging?.uploadURLWithClientToken,
            URL(string: "https://mobile-http-intake.logs.ddog-gov.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", logsEndpoint: .custom(url: "http://example.com/api")).logging?.uploadURLWithClientToken,
            URL(string: "http://example.com/api/abc")!
        )
    }

    // MARK: - Tracing Configuration Tests

    func testTracingConfiguration() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(tracingEnabled: false), appContext: .mockAny()).tracing,
            "Feature configuration should not be available if the feature is disabled"
        )

        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", tracesEndpoint: .us).tracing?.uploadURLWithClientToken,
            URL(string: "https://public-trace-http-intake.logs.datadoghq.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", tracesEndpoint: .eu).tracing?.uploadURLWithClientToken,
            URL(string: "https://public-trace-http-intake.logs.datadoghq.eu/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", tracesEndpoint: .gov).tracing?.uploadURLWithClientToken,
            URL(string: "https://public-trace-http-intake.logs.ddog-gov.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", tracesEndpoint: .custom(url: "http://example.com/api")).tracing?.uploadURLWithClientToken,
            URL(string: "http://example.com/api/abc")!
        )
    }

    // MARK: - RUM Configuration Tests

    func testRUMConfiguration() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(rumEnabled: false), appContext: .mockAny()).rum,
            "Feature configuration should not be available if the feature is disabled"
        )

        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", rumEndpoint: .us).rum?.uploadURLWithClientToken,
            URL(string: "https://rum-http-intake.logs.datadoghq.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", rumEndpoint: .eu).rum?.uploadURLWithClientToken,
            URL(string: "https://rum-http-intake.logs.datadoghq.eu/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", rumEndpoint: .gov).rum?.uploadURLWithClientToken,
            URL(string: "https://rum-http-intake.logs.ddog-gov.com/v1/input/abc")!
        )
        XCTAssertEqual(
            try createConfiguration(clientToken: "abc", rumEndpoint: .custom(url: "http://example.com/api")).rum?.uploadURLWithClientToken,
            URL(string: "http://example.com/api/abc")!
        )

        let custom = try FeaturesConfiguration(
            configuration: .mockWith(
                rumApplicationID: "rum-app-id",
                rumEnabled: true, rumSessionsSamplingRate: 45.2
            ),
            appContext: .mockAny()
        )
        XCTAssertEqual(custom.rum?.applicationID, "rum-app-id")
        XCTAssertEqual(custom.rum?.sessionSamplingRate, 45.2)
    }

    func testRUMAutoInstrumentationConfiguration() throws {
        let viewsConfigured = try FeaturesConfiguration(
            configuration: .mockWith(
                rumEnabled: true,
                rumUIKitViewsPredicate: UIKitRUMViewsPredicateMock(),
                rumUIKitActionsTrackingEnabled: false
            ),
            appContext: .mockAny()
        )
        XCTAssertNotNil(viewsConfigured.rum!.autoInstrumentation!.uiKitRUMViewsPredicate)
        XCTAssertFalse(viewsConfigured.rum!.autoInstrumentation!.uiKitActionsTrackingEnabled)

        let actionsConfigured = try FeaturesConfiguration(
            configuration: .mockWith(
                rumEnabled: true,
                rumUIKitViewsPredicate: nil,
                rumUIKitActionsTrackingEnabled: true
            ),
            appContext: .mockAny()
        )
        XCTAssertNil(actionsConfigured.rum!.autoInstrumentation!.uiKitRUMViewsPredicate)
        XCTAssertTrue(actionsConfigured.rum!.autoInstrumentation!.uiKitActionsTrackingEnabled)

        let viewsAndActionsNotConfigured = try FeaturesConfiguration(
            configuration: .mockWith(
                rumEnabled: true,
                rumUIKitViewsPredicate: nil,
                rumUIKitActionsTrackingEnabled: false
            ),
            appContext: .mockAny()
        )
        XCTAssertNil(
            viewsAndActionsNotConfigured.rum!.autoInstrumentation,
            "When neither Views nor Actions are configured, the auto instrumentation config shuld be `nil`"
        )
    }

    // MARK: - URLSession Auto Instrumentation Configuration Tests

    func testURLSessionAutoInstrumentationConfiguration() throws {
        let firstPartyHostsSet = try FeaturesConfiguration(
            configuration: .mockWith(firstPartyHosts: ["example.com", "foo.eu"]),
            appContext: .mockAny()
        )
        XCTAssertEqual(
            firstPartyHostsSet.urlSessionAutoInstrumentation?.userDefinedFirstPartyHosts,
            ["example.com", "foo.eu"]
        )
        XCTAssertEqual(
            firstPartyHostsSet.urlSessionAutoInstrumentation?.sdkInternalURLs,
            [
                Datadog.Configuration.LogsEndpoint.us.url,
                Datadog.Configuration.TracesEndpoint.us.url,
                Datadog.Configuration.RUMEndpoint.us.url
            ]
        )

        let firstPartyHostsNotSet = try FeaturesConfiguration(
            configuration: .mockWith(firstPartyHosts: nil),
            appContext: .mockAny()
        )
        XCTAssertNil(
            firstPartyHostsNotSet.urlSessionAutoInstrumentation,
            "When `firstPartyHosts` are not set, the URLSession auto instrumentation config shuld be `nil`"
        )

        let firstPartyHostsSetEmpty = try FeaturesConfiguration(
            configuration: .mockWith(firstPartyHosts: []),
            appContext: .mockAny()
        )
        XCTAssertNil(
            firstPartyHostsSetEmpty.urlSessionAutoInstrumentation,
            "When `firstPartyHosts` are set empty, the URLSession auto instrumentation config shuld be `nil`"
        )
    }

    // MARK: - Invalid Configurations

    func testWhenClientTokenIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try createConfiguration(clientToken: "")) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "🔥 Datadog SDK usage error: `clientToken` cannot be empty.")
        }
    }

    func testWhenCustomEndpointIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try createConfiguration(logsEndpoint: .custom(url: "not a valid url string"))) { error in
            XCTAssertEqual(
                (error as? ProgrammerError)?.description,
                "🔥 Datadog SDK usage error: The `url` in `.custom(url:)` must be a valid URL string."
            )
        }
    }

    func testGivenNoRUMApplicationIDProvided_whenRUMFeatureIsEnabled_itPrintsConsoleWarning() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        _ = try FeaturesConfiguration(
            configuration: .mockWith(rumApplicationID: nil, rumEnabled: true),
            appContext: .mockAny()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: In order to use the RUM feature, `Datadog.Configuration` must be constructed using:
            `.builderUsing(rumApplicationID:rumClientToken:environment:)`
            """
        )
    }

    // MARK: - Helpers

    private func createConfiguration(
        clientToken: String = "abc",
        logsEndpoint: Datadog.Configuration.LogsEndpoint = .us,
        tracesEndpoint: Datadog.Configuration.TracesEndpoint = .us,
        rumEndpoint: Datadog.Configuration.RUMEndpoint = .us
    ) throws -> FeaturesConfiguration {
        return try FeaturesConfiguration(
            configuration: .mockWith(
                clientToken: clientToken,
                loggingEnabled: true,
                tracingEnabled: true,
                rumEnabled: true,
                logsEndpoint: logsEndpoint,
                tracesEndpoint: tracesEndpoint,
                rumEndpoint: rumEndpoint
            ),
            appContext: .mockAny()
        )
    }
}
