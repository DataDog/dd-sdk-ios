/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct Environment {
    struct Variable {
        static let logsEndpoint     = "DD_MOCK_LOGS_ENDPOINT_URL"
        static let tracesEndpoint   = "DD_MOCK_TRACES_ENDPOINT_URL"
        static let rumEndpoint      = "DD_MOCK_RUM_ENDPOINT_URL"
        static let customEndpoint   = "DD_CUSTOM_ENDPOINT_URL"

        static let testScenarioIdentifier = "DD_TEST_SCENARIO_IDENTIFIER"
    }
    struct Argument {
        static let isRunningUnitTests   = "IS_RUNNING_UNIT_TESTS"
        static let isRunningUITests     = "IS_RUNNING_UI_TESTS"
    }
    struct InfoPlistKey {
        static let clientToken      = "DatadogClientToken"
        static let rumApplicationID = "RUMApplicationID"
    }

    // MARK: - Launch Arguments

    static func isRunningUnitTests() -> Bool {
        return ProcessInfo.processInfo.arguments.contains(Argument.isRunningUnitTests)
    }

    static func isRunningUITests() -> Bool {
        return ProcessInfo.processInfo.arguments.contains(Argument.isRunningUITests)
    }

    // MARK: - Launch Variables

    static func testScenario() -> TestScenario? {
        guard let envIdentifier = ProcessInfo.processInfo.environment[Variable.testScenarioIdentifier] else {
            return nil
        }

        return createTestScenario(for: envIdentifier)
    }

    static func logsEndpoint() -> String? {
        return ProcessInfo.processInfo.environment[Variable.logsEndpoint]
    }

    static func tracesEndpoint() -> String? {
        return ProcessInfo.processInfo.environment[Variable.tracesEndpoint]
    }

    static func rumEndpoint() -> String? {
        return ProcessInfo.processInfo.environment[Variable.rumEndpoint]
    }

    static func customEndpointURL() -> URL? {
        if let customEndpoint = ProcessInfo.processInfo.environment[Variable.customEndpoint] {
            return URL(string: customEndpoint)!
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
}
