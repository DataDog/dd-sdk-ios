/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class InternalLoggersTests: XCTestCase {
    private let internalLoggerConfigurationMock = InternalLoggerConfiguration(
        sdkVersion: .mockAny(),
        applicationVersion: .mockAny(),
        environment: .mockAny(),
        userInfoProvider: UserInfoProvider.mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderMock.mockAny()
    )

    // MARK: - User Logger

    func testWhenSDKIsNotInitialized_itUsesNoOpUserLogger() {
        XCTAssertNil(userLogger.logBuilder)
        XCTAssertNil(userLogger.logOutput)
    }

    func testGivenDefaultSDKConfiguration_whenInitialized_itUsesWorkingUserLogger() {
        let defaultSDKConfiguration = DatadogSDK.Configuration.builderUsing(clientToken: "abc", environment: "test").build()
        DatadogSDK.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: defaultSDKConfiguration
        )
        XCTAssertTrue((userLogger.logOutput as? ConditionalLogOutput)?.conditionedOutput is LogConsoleOutput)
        DatadogSDK.flushAndDeinitialize()
    }

    func testGivenLoggingFeatureDisabled_whenSDKisInitialized_itUsesWorkingUserLogger() {
        DatadogSDK.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: .mockWith(loggingEnabled: false)
        )
        XCTAssertTrue((userLogger.logOutput as? ConditionalLogOutput)?.conditionedOutput is LogConsoleOutput)
        DatadogSDK.flushAndDeinitialize()
    }

    func testUserLoggerPrintsMessagesAboveGivenVerbosityLevel() {
        var printedMessages: [String] = []

        let userLogger = createSDKUserLogger(
            configuration: internalLoggerConfigurationMock,
            consolePrintFunction: { printedMessages.append($0) },
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            timeZone: .EET
        )

        let expectedMessages = [
            "[DATADOG SDK] 🐶 → 12:00:00.000 [DEBUG] message",
            "[DATADOG SDK] 🐶 → 12:00:00.000 [INFO] message",
            "[DATADOG SDK] 🐶 → 12:00:00.000 [NOTICE] message",
            "[DATADOG SDK] 🐶 → 12:00:00.000 [WARN] message",
            "[DATADOG SDK] 🐶 → 12:00:00.000 [ERROR] message",
            "[DATADOG SDK] 🐶 → 12:00:00.000 [CRITICAL] message"
        ]

        XCTAssertNil(DatadogSDK.verbosityLevel)
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, [])

        printedMessages = []
        DatadogSDK.verbosityLevel = .debug
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[0..<expectedMessages.count]))

        printedMessages = []
        DatadogSDK.verbosityLevel = .info
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[1..<expectedMessages.count]))

        printedMessages = []
        DatadogSDK.verbosityLevel = .notice
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[2..<expectedMessages.count]))

        printedMessages = []
        DatadogSDK.verbosityLevel = .warn
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[3..<expectedMessages.count]))

        printedMessages = []
        DatadogSDK.verbosityLevel = .error
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[4..<expectedMessages.count]))

        printedMessages = []
        DatadogSDK.verbosityLevel = .critical
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[5..<expectedMessages.count]))

        DatadogSDK.verbosityLevel = nil
    }

    // MARK: - Helpers

    private func logMessageUsingAllLevels(_ message: String, with logger: Logger) {
        logger.debug(message)
        logger.info(message)
        logger.notice(message)
        logger.warn(message)
        logger.error(message)
        logger.critical(message)
    }
}
