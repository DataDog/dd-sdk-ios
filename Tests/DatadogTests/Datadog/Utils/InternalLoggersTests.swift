/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class InternalLoggersTests: XCTestCase {
    private let internalLoggerConfigurationMock = InternalLoggerConfiguration(
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
        let defaultSDKConfiguration = Datadog.Configuration.builderUsing(clientToken: "abc", environment: "test").build()
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: defaultSDKConfiguration
        )
        XCTAssertTrue((userLogger.logOutput as? ConditionalLogOutput)?.conditionedOutput is LogConsoleOutput)
        Datadog.deinitialize()
    }

    func testGivenLoggingFeatureDisabled_whenSDKisInitialized_itUsesWorkingUserLogger() {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: .mockWith(loggingEnabled: false)
        )
        XCTAssertTrue((userLogger.logOutput as? ConditionalLogOutput)?.conditionedOutput is LogConsoleOutput)
        Datadog.deinitialize()
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

        XCTAssertNil(Datadog.verbosityLevel)
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, [])

        printedMessages = []
        Datadog.verbosityLevel = .debug
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[0..<expectedMessages.count]))

        printedMessages = []
        Datadog.verbosityLevel = .info
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[1..<expectedMessages.count]))

        printedMessages = []
        Datadog.verbosityLevel = .notice
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[2..<expectedMessages.count]))

        printedMessages = []
        Datadog.verbosityLevel = .warn
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[3..<expectedMessages.count]))

        printedMessages = []
        Datadog.verbosityLevel = .error
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[4..<expectedMessages.count]))

        printedMessages = []
        Datadog.verbosityLevel = .critical
        logMessageUsingAllLevels("message", with: userLogger)
        XCTAssertEqual(printedMessages, Array(expectedMessages[5..<expectedMessages.count]))

        Datadog.verbosityLevel = nil
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
