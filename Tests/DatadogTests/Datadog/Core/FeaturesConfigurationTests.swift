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
        let clientToken: String = .mockRandom(among: "abcdefgh")
        let configuration = try createConfiguration(clientToken: clientToken)

        XCTAssertEqual(configuration.logging?.clientToken, clientToken)
        XCTAssertEqual(configuration.tracing?.clientToken, clientToken)
        XCTAssertEqual(configuration.rum?.clientToken, clientToken)
        XCTAssertNotEqual(configuration.internalMonitoring?.clientToken, clientToken)
    }

    func testEndpoint() throws {
        let randomLogsEndpoint: Datadog.Configuration.LogsEndpoint = .mockRandom()
        let randomTracesEndpoint: Datadog.Configuration.TracesEndpoint = .mockRandom()
        let randomRUMEndpoint: Datadog.Configuration.RUMEndpoint = .mockRandom()

        func configuration(datadogEndpoint: Datadog.Configuration.DatadogEndpoint?) throws -> FeaturesConfiguration {
            try createConfiguration(
                datadogEndpoint: datadogEndpoint,
                logsEndpoint: randomLogsEndpoint,
                tracesEndpoint: randomTracesEndpoint,
                rumEndpoint: randomRUMEndpoint
            )
        }

        typealias DeprecatedEndpoints = Deprecated<Datadog.Configuration.DatadogEndpoint>

        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-datadoghq.com/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us3).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-us3-datadoghq.com/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us5).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-us5-datadoghq.com/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .eu1).logging?.uploadURL.absoluteString,
            "https://mobile-http-intake.logs.datadoghq.eu/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1_fed).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-ddog-gov.com/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.us).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-datadoghq.com/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.eu).logging?.uploadURL.absoluteString,
            "https://mobile-http-intake.logs.datadoghq.eu/api/v2/logs"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.gov).logging?.uploadURL.absoluteString,
            "https://logs.browser-intake-ddog-gov.com/api/v2/logs"
        )

        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-datadoghq.com/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us3).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-us3-datadoghq.com/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us5).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-us5-datadoghq.com/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .eu1).tracing?.uploadURL.absoluteString,
            "https:/public-trace-http-intake.logs.datadoghq.eu/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1_fed).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-ddog-gov.com/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.us).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-datadoghq.com/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.eu).tracing?.uploadURL.absoluteString,
            "https:/public-trace-http-intake.logs.datadoghq.eu/api/v2/spans"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.gov).tracing?.uploadURL.absoluteString,
            "https://trace.browser-intake-ddog-gov.com/api/v2/spans"
        )

        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-datadoghq.com/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us3).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-us3-datadoghq.com/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us5).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-us5-datadoghq.com/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .eu1).rum?.uploadURL.absoluteString,
            "https://rum-http-intake.logs.datadoghq.eu/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: .us1_fed).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-ddog-gov.com/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.us).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-datadoghq.com/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.eu).rum?.uploadURL.absoluteString,
            "https://rum-http-intake.logs.datadoghq.eu/api/v2/rum"
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: DeprecatedEndpoints.gov).rum?.uploadURL.absoluteString,
            "https://rum.browser-intake-ddog-gov.com/api/v2/rum"
        )

        XCTAssertEqual(
            try configuration(datadogEndpoint: nil).logging?.uploadURL.absoluteString,
            randomLogsEndpoint.url,
            "When `DatadogEndpoint` is not set, it should default to `LogsEndpoint` value."
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: nil).tracing?.uploadURL.absoluteString,
            randomTracesEndpoint.url,
            "When `DatadogEndpoint` is not set, it should default to `TracesEndpoint` value."
        )
        XCTAssertEqual(
            try configuration(datadogEndpoint: nil).rum?.uploadURL.absoluteString,
            randomRUMEndpoint.url,
            "When `DatadogEndpoint` is not set, it should default to `RUMEndpoint` value."
        )
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

    // MARK: - Logging Configuration Tests

    func testWhenLoggingIsDisabled() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(loggingEnabled: false), appContext: .mockAny()).logging,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    func testCustomLogsEndpoint() throws {
        let randomDatadogEndpoint: Datadog.Configuration.DatadogEndpoint = .mockRandom()
        let randomCustomEndpoint: URL = .mockRandom()

        let configuration = try createConfiguration(
            datadogEndpoint: randomDatadogEndpoint,
            customLogsEndpoint: randomCustomEndpoint
        )

        XCTAssertEqual(
            configuration.logging?.uploadURL,
            randomCustomEndpoint,
            "When custom endpoint is set it should override `DatadogEndpoint`"
        )
    }

    // MARK: - Tracing Configuration Tests

    func testWhenTracingIsDisabled() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(tracingEnabled: false), appContext: .mockAny()).tracing,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    func testCustomTracesEndpoint() throws {
        let randomDatadogEndpoint: Datadog.Configuration.DatadogEndpoint = .mockRandom()
        let randomCustomEndpoint: URL = .mockRandom()

        let configuration = try createConfiguration(
            datadogEndpoint: randomDatadogEndpoint,
            customTracesEndpoint: randomCustomEndpoint
        )

        XCTAssertEqual(
            configuration.tracing?.uploadURL,
            randomCustomEndpoint,
            "When custom endpoint is set it should override `DatadogEndpoint`"
        )
    }

    // MARK: - RUM Configuration Tests

    func testWhenRUMIsDisabled() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(rumEnabled: false), appContext: .mockAny()).rum,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    func testCustomRUMEndpoint() throws {
        let randomDatadogEndpoint: Datadog.Configuration.DatadogEndpoint = .mockRandom()
        let randomCustomEndpoint: URL = .mockRandom()

        let configuration = try createConfiguration(
            datadogEndpoint: randomDatadogEndpoint,
            customRUMEndpoint: randomCustomEndpoint
        )

        XCTAssertEqual(
            configuration.rum?.uploadURL,
            randomCustomEndpoint,
            "When custom endpoint is set it should override `DatadogEndpoint`"
        )
    }

    func testRUMSamplingRate() throws {
        let custom = try FeaturesConfiguration(
            configuration: .mockWith(
                rumApplicationID: "rum-app-id",
                rumEnabled: true,
                rumSessionsSamplingRate: 45.2
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
                rumUIKitUserActionsPredicate: nil,
                rumLongTaskDurationThreshold: nil
            ),
            appContext: .mockAny()
        )
        XCTAssertNotNil(viewsConfigured.rum!.instrumentation!.uiKitRUMViewsPredicate)
        XCTAssertNil(viewsConfigured.rum!.instrumentation!.uiKitRUMUserActionsPredicate)
        XCTAssertNil(viewsConfigured.rum!.instrumentation!.longTaskThreshold)

        let actionsConfigured = try FeaturesConfiguration(
            configuration: .mockWith(
                rumEnabled: true,
                rumUIKitViewsPredicate: nil,
                rumUIKitUserActionsPredicate: UIKitRUMUserActionsPredicateMock(),
                rumLongTaskDurationThreshold: nil
            ),
            appContext: .mockAny()
        )

        XCTAssertNotNil(actionsConfigured.rum!.instrumentation!.uiKitRUMUserActionsPredicate)
        XCTAssertNil(actionsConfigured.rum!.instrumentation!.uiKitRUMViewsPredicate)
        XCTAssertNil(actionsConfigured.rum!.instrumentation!.longTaskThreshold)

        let longTaskConfigured = try FeaturesConfiguration(
            configuration: .mockWith(
                rumEnabled: true,
                rumUIKitViewsPredicate: nil,
                rumUIKitUserActionsPredicate: nil,
                rumLongTaskDurationThreshold: 0.25
            ),
            appContext: .mockAny()
        )

        XCTAssertNotNil(longTaskConfigured.rum!.instrumentation!.longTaskThreshold)
        XCTAssertNil(longTaskConfigured.rum!.instrumentation!.uiKitRUMViewsPredicate)
        XCTAssertNil(longTaskConfigured.rum!.instrumentation!.uiKitRUMUserActionsPredicate)
    }

    // MARK: - Crash Reporting Configuration Tests

    func testWhenCrashReportingIsDisabled() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(crashReportingPlugin: nil), appContext: .mockAny()).crashReporting,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    func testWhenRUMorLoggingFeaturesAreEnabled_thenCrashReportingFeatureCanBeEnabled() throws {
        let random = [true, true, false].shuffled() // get at least one `true` on first two positions
        let enableLogging = random[0]
        let enableRUM = random[1]

        XCTAssertNotNil(
            try FeaturesConfiguration(
                configuration: .mockWith(
                    loggingEnabled: enableLogging,
                    rumEnabled: enableRUM,
                    crashReportingPlugin: CrashReportingPluginMock()
                ),
                appContext: .mockAny()
            ).crashReporting,
            """
            When Logging is \(enableLogging ? "" : "dis")abled and RUM is \(enableRUM ? "" : "dis")abled,
            then Crash Reporting should be enabled.
            """
        )
    }

    func testGivenRUMAndLoggingFeaturesDisabled_whenCrashReportingFeatureIsEnabled_itPrintsConsoleWarning() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        _ = try FeaturesConfiguration(
            configuration: .mockWith(
                loggingEnabled: false,
                rumEnabled: false,
                crashReportingPlugin: CrashReportingPluginMock()
            ),
            appContext: .mockAny()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: To use `.enableCrashReporting(using:)` either RUM or Logging must be enabled.
            Use: `.enableLogging(true)` or `.enableRUM(true)`.
            """
        )
    }

    // MARK: - URLSession Auto Instrumentation Configuration Tests

    func testURLSessionAutoInstrumentationConfiguration() throws {
        let randomDatadogEndpoint: Datadog.Configuration.DatadogEndpoint = .mockRandom()
        let randomCustomLogsEndpoint: URL? = Bool.random() ? .mockRandom() : nil
        let randomCustomTracesEndpoint: URL? = Bool.random() ? .mockRandom() : nil
        let randomCustomRUMEndpoint: URL? = Bool.random() ? .mockRandom() : nil

        let firstPartyHosts: Set<String> = ["example.com", "foo.eu"]
        let expectedSDKInternalURLs: Set<String> = [
            randomCustomLogsEndpoint?.absoluteString ?? randomDatadogEndpoint.logsEndpoint.url,
            randomCustomTracesEndpoint?.absoluteString ?? randomDatadogEndpoint.tracesEndpoint.url,
            randomCustomRUMEndpoint?.absoluteString ?? randomDatadogEndpoint.rumEndpoint.url
        ]

        func createConfiguration(
            tracingEnabled: Bool,
            rumEnabled: Bool,
            firstPartyHosts: Set<String>?
        ) throws -> FeaturesConfiguration {
            try FeaturesConfiguration(
                configuration: .mockWith(
                    tracingEnabled: tracingEnabled,
                    rumEnabled: rumEnabled,
                    datadogEndpoint: randomDatadogEndpoint,
                    customLogsEndpoint: randomCustomLogsEndpoint,
                    customTracesEndpoint: randomCustomTracesEndpoint,
                    customRUMEndpoint: randomCustomRUMEndpoint,
                    firstPartyHosts: firstPartyHosts
                ),
                appContext: .mockAny()
            )
        }

        // When `firstPartyHosts` are provided and both Tracing and RUM are enabled
        var configuration = try createConfiguration(
            tracingEnabled: true,
            rumEnabled: true,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.userDefinedFirstPartyHosts, firstPartyHosts)
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.sdkInternalURLs, expectedSDKInternalURLs)
        XCTAssertTrue(configuration.urlSessionAutoInstrumentation!.instrumentTracing)
        XCTAssertTrue(configuration.urlSessionAutoInstrumentation!.instrumentRUM)

        // When `firstPartyHosts` are set and only Tracing is enabled
        configuration = try createConfiguration(
            tracingEnabled: true,
            rumEnabled: false,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.userDefinedFirstPartyHosts, firstPartyHosts)
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.sdkInternalURLs, expectedSDKInternalURLs)
        XCTAssertTrue(configuration.urlSessionAutoInstrumentation!.instrumentTracing)
        XCTAssertFalse(configuration.urlSessionAutoInstrumentation!.instrumentRUM)

        // When `firstPartyHosts` are set and only RUM is enabled
        configuration = try createConfiguration(
            tracingEnabled: false,
            rumEnabled: true,
            firstPartyHosts: firstPartyHosts
        )
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.userDefinedFirstPartyHosts, firstPartyHosts)
        XCTAssertEqual(configuration.urlSessionAutoInstrumentation?.sdkInternalURLs, expectedSDKInternalURLs)
        XCTAssertFalse(configuration.urlSessionAutoInstrumentation!.instrumentTracing)
        XCTAssertTrue(configuration.urlSessionAutoInstrumentation!.instrumentRUM)

        // When `firstPartyHosts` are not set
        configuration = try createConfiguration(
            tracingEnabled: true,
            rumEnabled: true,
            firstPartyHosts: nil
        )
        XCTAssertNil(
            configuration.urlSessionAutoInstrumentation,
            "When `firstPartyHosts` are not set, the URLSession auto instrumentation config should be `nil`"
        )

        // When `firstPartyHosts` are set empty
        configuration = try createConfiguration(
            tracingEnabled: true,
            rumEnabled: true,
            firstPartyHosts: []
        )
        XCTAssertNotNil(
            configuration.urlSessionAutoInstrumentation,
            "When `firstPartyHosts` are set empty and non-nil, the URLSession auto instrumentation config should NOT be nil."
        )
    }

    func testWhenURLSessionAutoinstrumentationEnabled_thenRUMAttributesProviderCanBeConfigured() throws {
        // When
        let configurationWithAttributesProvider = try FeaturesConfiguration(
            configuration: .mockWith(
                tracingEnabled: .random(),
                rumEnabled: true,
                firstPartyHosts: ["foo.com"],
                rumResourceAttributesProvider: { _, _, _, _ in [:] }
            ),
            appContext: .mockAny()
        )
        let configurationWithoutAttributesProvider = try FeaturesConfiguration(
            configuration: .mockWith(
                tracingEnabled: .random(),
                rumEnabled: true,
                firstPartyHosts: ["foo.com"],
                rumResourceAttributesProvider: nil
            ),
            appContext: .mockAny()
        )

        // Then
        XCTAssertNotNil(configurationWithAttributesProvider.urlSessionAutoInstrumentation?.rumAttributesProvider)
        XCTAssertNil(configurationWithoutAttributesProvider.urlSessionAutoInstrumentation?.rumAttributesProvider)
    }

    func testGivenURLSessionAutoinstrumentationDisabled_whenRUMAttributesProviderIsSet_itPrintsConsoleWarning() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        _ = try FeaturesConfiguration(
            configuration: .mockWith(
                firstPartyHosts: nil,
                rumResourceAttributesProvider: { _, _, _, _ in nil }
            ),
            appContext: .mockAny()
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: To use `.setRUMResourceAttributesProvider(_:)` URLSession tracking must be enabled
            with `.trackURLSession(firstPartyHosts:)`.
            """
        )
    }

    // MARK: - Internal Monitoring Configuration Tests

    func testWhenInternalMonitoringIsDisabled() throws {
        XCTAssertNil(
            try FeaturesConfiguration(configuration: .mockWith(internalMonitoringClientToken: nil), appContext: .mockAny()).internalMonitoring,
            "Feature configuration should not be available if the feature is disabled"
        )
    }

    func testWhenInternalMonitoringClientTokenIsSet_thenInternalMonitoringConfigurationIsEnabled() throws {
        // When
        let internalMonitoringClientToken: String = .mockRandom(among: "abcdef")
        let featuresClientToken: String = .mockRandom(among: "ghijkl")
        let featuresConfiguration = try FeaturesConfiguration(
            configuration: .mockWith(
                clientToken: featuresClientToken,
                loggingEnabled: true,
                tracingEnabled: true,
                rumEnabled: true,
                internalMonitoringClientToken: internalMonitoringClientToken
            ),
            appContext: .mockAny()
        )

        // Then
        let configuration = try XCTUnwrap(featuresConfiguration.internalMonitoring)
        XCTAssertEqual(configuration.common, featuresConfiguration.common)
        XCTAssertEqual(configuration.sdkServiceName, "dd-sdk-ios", "Internal monitoring data should be available under \"service:dd-sdk-ios\"")
        XCTAssertEqual(configuration.sdkEnvironment, "prod", "Internal monitoring data should be available under \"env:prod\"")
        XCTAssertEqual(
            configuration.logsUploadURL.absoluteString,
            "https://logs.browser-intake-datadoghq.com/api/v2/logs"
        )
        XCTAssertEqual(configuration.clientToken, internalMonitoringClientToken, "Internal Monitoring must use monitoring token")
        XCTAssertEqual(featuresConfiguration.logging!.clientToken, featuresClientToken, "Logging must use feature token")
        XCTAssertEqual(featuresConfiguration.tracing!.clientToken, featuresClientToken, "Tracing must use feature token")
        XCTAssertEqual(featuresConfiguration.rum!.clientToken, featuresClientToken, "RUM must use feature token")
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

    func testGivenFirstPartyHostsDefined_whenRUMAndTracingAreDisabled_itDoesNotInstrumentURLSessionAndPrintsConsoleWarning() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // Given
        let firstPartyHosts: Set<String> = ["first-party.com"]

        // When
        let tracingEnabled = false
        let rumEnabled = false

        // Then
        let configuration = try FeaturesConfiguration(
            configuration: .mockWith(tracingEnabled: tracingEnabled, rumEnabled: rumEnabled, firstPartyHosts: firstPartyHosts),
            appContext: .mockAny()
        )

        XCTAssertNil(
            configuration.urlSessionAutoInstrumentation,
            "`URLSession` should not be auto instrumented."
        )

        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: To use `.trackURLSession(firstPartyHosts:)` either RUM or Tracing must be enabled.
            Use: `.enableTracing(true)` or `.enableRUM(true)`.
            """
        )
    }

    func testWhenSomeOfTheFirstPartyHostsAreMistaken_itPrintsWarningsAndDoesSanitization() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // When
        let firstPartyHosts: Set<String> = [
            "https://first-party.com", // sanitize to → "first-party.com"
            "http://api.first-party.com", // sanitize to → "api.first-party.com"
            "https://first-party.com/v2/api", // sanitize to → "first-party.com"
            "https://192.168.0.1/api", // sanitize to → "192.168.0.1"
            "https://192.168.0.2", // sanitize to → "192.168.0.2"
            "invalid-host-name", // drop
            "192.168.0.3:8080", // drop
            "", // drop
            "localhost", // accept
            "192.168.0.4", // accept
            "valid-host-name.com", // accept
        ]

        // Then
        let configuration = try FeaturesConfiguration(
            configuration: .mockWith(rumEnabled: true, firstPartyHosts: firstPartyHosts),
            appContext: .mockAny()
        )

        XCTAssertEqual(
            configuration.urlSessionAutoInstrumentation?.userDefinedFirstPartyHosts,
            [
                "first-party.com",
                "api.first-party.com",
                "localhost",
                "192.168.0.1",
                "192.168.0.2",
                "localhost",
                "192.168.0.4",
                "valid-host-name.com"
            ]
        )

        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: '192.168.0.3:8080' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: '' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'https://first-party.com' is an url and will be sanitized to: 'first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'https://192.168.0.1/api' is an url and will be sanitized to: '192.168.0.1'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'http://api.first-party.com' is an url and will be sanitized to: 'api.first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'https://first-party.com/v2/api' is an url and will be sanitized to: 'first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'invalid-host-name' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ The first party host configured for Datadog SDK is not valid: 'https://192.168.0.2' is an url and will be sanitized to: '192.168.0.2'.")
        )
        XCTAssertEqual(printFunction.printedMessages.count, 8)
    }

    // MARK: - Helpers

    private func createConfiguration(
        clientToken: String = "abc",
        datadogEndpoint: Datadog.Configuration.DatadogEndpoint? = nil,
        customLogsEndpoint: URL? = nil,
        customTracesEndpoint: URL? = nil,
        customRUMEndpoint: URL? = nil,
        logsEndpoint: Datadog.Configuration.LogsEndpoint = .us1,
        tracesEndpoint: Datadog.Configuration.TracesEndpoint = .us1,
        rumEndpoint: Datadog.Configuration.RUMEndpoint = .us1,
        proxyConfiguration: [AnyHashable: Any]? = nil
    ) throws -> FeaturesConfiguration {
        return try FeaturesConfiguration(
            configuration: .mockWith(
                clientToken: clientToken,
                loggingEnabled: true,
                tracingEnabled: true,
                rumEnabled: true,
                datadogEndpoint: datadogEndpoint,
                customLogsEndpoint: customLogsEndpoint,
                customTracesEndpoint: customTracesEndpoint,
                customRUMEndpoint: customRUMEndpoint,
                logsEndpoint: logsEndpoint,
                tracesEndpoint: tracesEndpoint,
                rumEndpoint: rumEndpoint,
                proxyConfiguration: proxyConfiguration
            ),
            appContext: .mockAny()
        )
    }
}

// MARK: - Deprecation Helpers

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol DeprecatedDatadogEndpoints {
    static var us: Self { get }
    static var eu: Self { get }
    static var gov: Self { get }
}
extension Datadog.Configuration.DatadogEndpoint: DeprecatedDatadogEndpoints {}

/// An assistant shim to access `Datadog.Configuration.DatadogEndpoint` deprecated APIs with no warning.
private struct Deprecated<T: DeprecatedDatadogEndpoints> {
    static var us: T { T.us }
    static var eu: T { T.eu }
    static var gov: T { T.gov }
}
