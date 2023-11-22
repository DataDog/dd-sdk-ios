/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Encapsulates Python server configuration passed through ENV variable from  UITest runner to the app process.
internal struct HTTPServerMockConfiguration: Codable {
    /// Python server URL to record Logging requests.
    var logsEndpoint: URL? = nil
    /// Python server URL to record Tracing requests.
    var tracesEndpoint: URL? = nil
    /// Python server URL to record RUM requests.
    var rumEndpoint: URL? = nil
    /// Python server URL to record Session Replay requests.
    var srEndpoint: URL? = nil

    /// Python server URLs to record custom requests, e.g. custom data requests
    /// to assert trace headers propagation.
    var instrumentedEndpoints: [URL] = []

    // MARK: - Coding

    /// Encodes this struct to base-64 encoded string so it can be passed in ENV variable.
    var toEnvironmentValue: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return data.base64EncodedString()
    }

    /// Decodes this struct from base-64 encoded string so it can be read from ENV variable.
    fileprivate static func from(environmentValue: String) -> HTTPServerMockConfiguration {
        let decoder = JSONDecoder()
        let data = Data(base64Encoded: environmentValue)!
        return try! decoder.decode(HTTPServerMockConfiguration.self, from: data)
    }
}

/// Defines the way of instrumenting `URLSession` for RUM and Tracing scenarios.
internal struct URLSessionSetup: Codable {
    /// The method of instrumenting `URLSession` with `DDURLSessionDelegate` and providing `firstPartyHosts`
    /// information to RUM and Tracing.
    enum InstrumentationMethod: CaseIterable, Codable {
        /// Use `DDURLSessionDelegate` class directly.
        /// and define `firstPartyHosts` in feature configuration.
        case directWithFeatureFirstPartyHosts
        /// Use `DDURLSessionDelegate` class directly
        /// and define `firstPartyHosts` with delegate's configuration.
        case directWithAdditionalFirstyPartyHosts
        /// Use `DDURLSessionDelegate` by inheriting it in a subclass (see: `InheritedURLSessionDelegate`).
        /// and define `firstPartyHosts` in feature configuration.
        case inheritance
        /// Use `DDURLSessionDelegate` by compositing it custom delegate class (see: `CompositedURLSessionDelegate`).
        /// and define `firstPartyHosts` in feature configuration.
        case composition
        /// Use a custom delegate.
        /// and define `firstPartyHosts` in feature configuration.
        case customWithFeatureFirstPartyHosts
        /// Use a custom delegate.
        /// and define `firstPartyHosts` with delegate's configuration.
        case customWithAdditionalFirstyPartyHosts
    }

    /// A method of instrumenting `URLSession` with `DDURLSessionDelegate`.
    let instrumentationMethod: InstrumentationMethod

    /// The moment of initializing `URLSession` (and `DDURLSessionDelegate`) in relation to starting SDK.
    enum InitializationMethod: CaseIterable, Codable {
        /// Initialize `URLSession` (and delegate) before starting SDK.
        case beforeSDK
        /// Initialize `URLSession` (and delegate) after starting SDK.
        case afterSDK
    }

    /// A method of initializing `URLSession` (and `DDURLSessionDelegate`).
    let initializationMethod: InitializationMethod

    // MARK: - Coding

    /// Encodes this struct to base-64 encoded string so it can be passed in ENV variable.
    var toEnvironmentValue: String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return data.base64EncodedString()
    }

    /// Decodes this struct from base-64 encoded string so it can be read from ENV variable.
    fileprivate static func from(environmentValue: String) -> URLSessionSetup {
        let decoder = JSONDecoder()
        let data = Data(base64Encoded: environmentValue)!
        return try! decoder.decode(URLSessionSetup.self, from: data)
    }
}

internal struct Environment {
    /// ENV variables shared between UITests and Example targets.
    struct Variable {
        static let testScenarioClassName = "DD_TEST_SCENARIO_CLASS_NAME"
        static let serverMockConfiguration = "DD_TEST_SERVER_MOCK_CONFIGURATION"
        static let urlSessionSetup = "DD_TEST_URL_SESSION_SETUP"
    }
    /// Launch arguments shared between UITests and Example targets.
    struct Argument {
        static let isRunningUnitTests       = "IS_RUNNING_UNIT_TESTS"
        static let isRunningUITests         = "IS_RUNNING_UI_TESTS"
        static let doNotClearPersistentData = "DO_NOT_CLEAR_PERSISTENT_DATA"
    }
    /// Common constants shared between UITests and Example targets.
    struct Constants {
        /// The name of the view indicating the end of RUM session in RUM-related `TestScenarios`.
        static let rumSessionEndViewName = "RUMSessionEndView"
    }
    struct InfoPlistKey {
        static let clientToken      = "DatadogClientToken"
        static let rumApplicationID = "RUMApplicationID"

        static let customLogsURL    = "CustomLogsURL"
        static let customTraceURL   = "CustomTraceURL"
        static let customRUMURL     = "CustomRUMURL"
    }

    // MARK: - Launch Arguments

    static func isRunningUnitTests() -> Bool {
        return ProcessInfo.processInfo.arguments.contains(Argument.isRunningUnitTests)
    }

    static func isRunningUITests() -> Bool {
        return ProcessInfo.processInfo.arguments.contains(Argument.isRunningUITests)
    }

    /// If running `Example` in interactive, debug mode (launching it with 'Run' in Xcode or by tapping on the app icon).
    static func isRunningInteractive() -> Bool {
        return !isRunningUITests() && !isRunningUnitTests()
    }

    static func shouldClearPersistentData() -> Bool {
        return !ProcessInfo.processInfo.arguments.contains(Argument.doNotClearPersistentData)
    }

    // MARK: - Launch Variables

    static func testScenarioClassName() -> String? {
        return ProcessInfo.processInfo.environment[Variable.testScenarioClassName]
    }

    static func serverMockConfiguration() -> HTTPServerMockConfiguration? {
        if let environmentValue = ProcessInfo.processInfo.environment[Variable.serverMockConfiguration] {
            return HTTPServerMockConfiguration.from(environmentValue: environmentValue)
        }
        return nil
    }

    static func urlSessionSetup() -> URLSessionSetup? {
        if let environmentValue = ProcessInfo.processInfo.environment[Variable.urlSessionSetup] {
            return URLSessionSetup.from(environmentValue: environmentValue)
        }
        return nil
    }

    // MARK: - Info.plist

    static func readClientToken() -> String {
        guard let clientToken = Bundle.main.infoDictionary?[InfoPlistKey.clientToken] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `\(InfoPlistKey.clientToken)` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }
        return clientToken
    }

    static func readRUMApplicationID() -> String {
        guard let rumApplicationID = Bundle.main.infoDictionary![InfoPlistKey.rumApplicationID] as? String, !rumApplicationID.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `\(InfoPlistKey.rumApplicationID)` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            RUM application id obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }
        return rumApplicationID
    }

    static func readCustomLogsURL() -> URL? {
        if let customLogsURL = Bundle.main.infoDictionary![InfoPlistKey.customLogsURL] as? String,
           !customLogsURL.isEmpty {
            return URL(string: "https://\(customLogsURL)")
        }
        return nil
    }

    static func readCustomTraceURL() -> URL? {
        if let customTraceURL = Bundle.main.infoDictionary![InfoPlistKey.customTraceURL] as? String,
           !customTraceURL.isEmpty {
            return URL(string: "https://\(customTraceURL)")
        }
        return nil
    }

    static func readCustomRUMURL() -> URL? {
        if let customRUMURL = Bundle.main.infoDictionary![InfoPlistKey.customRUMURL] as? String,
           !customRUMURL.isEmpty {
            return URL(string: "https://\(customRUMURL)")
        }
        return nil
    }
}
