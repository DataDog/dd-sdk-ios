/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class InternalLoggersTests: XCTestCase {
    private var printedMessages: [String]! // swiftlint:disable:this implicitly_unwrapped_optional
    private var userLogger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
        LoggingFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        printedMessages = []
        userLogger = createSDKUserLogger(
            consolePrintFunction: { [weak self] in self?.printedMessages.append($0) },
            dateProvider: RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC()),
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
    }

    override func tearDown() {
        printedMessages = nil
        userLogger = nil
        Datadog.verbosityLevel = nil
        LoggingFeature.instance = nil
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - `userLogger`

    private func logMessageUsingAllLevels(_ message: String) {
        userLogger.debug(message)
        userLogger.info(message)
        userLogger.notice(message)
        userLogger.warn(message)
        userLogger.error(message)
        userLogger.critical(message)
    }

    private let expectedMessages = [
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [DEBUG] message",
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [INFO] message",
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [NOTICE] message",
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [WARN] message",
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [ERROR] message",
        "[DATADOG SDK] 🐶 → 10:00:00.000Z [CRITICAL] message"
    ]

    func testUserLoggerDoesNothingWithDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, [])
    }

    func testUserLoggerPrintsWithVerbosityLevel_debug() {
        Datadog.verbosityLevel = .debug
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[0..<expectedMessages.count]))
    }

    func testUserLoggerPrintsWithVerbosityLevel_info() {
        Datadog.verbosityLevel = .info
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[1..<expectedMessages.count]))
    }

    func testUserLoggerPrintsWithVerbosityLevel_notice() {
        Datadog.verbosityLevel = .notice
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[2..<expectedMessages.count]))
    }

    func testUserLoggerPrintsWithVerbosityLevel_warn() {
        Datadog.verbosityLevel = .warn
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[3..<expectedMessages.count]))
    }

    func testUserLoggerPrintsWithVerbosityLevel_error() {
        Datadog.verbosityLevel = .error
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[4..<expectedMessages.count]))
    }

    func testUserLoggerPrintsWithVerbosityLevel_critical() {
        Datadog.verbosityLevel = .critical
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[5..<expectedMessages.count]))
    }

    // MARK: - `developerLogger`

    func testWhenCompileNotForDevelopment_DeveloperLoggerIsNotAvailable() {
        let originalValue = CompilationConditions.isSDKCompiledForDevelopment
        defer { CompilationConditions.isSDKCompiledForDevelopment = originalValue }

        CompilationConditions.isSDKCompiledForDevelopment = false

        XCTAssertNil(createSDKDeveloperLogger())
    }

    func testWhenCompileForDevelopment_DeveloperLoggerIsAvailable() {
        let originalValue = CompilationConditions.isSDKCompiledForDevelopment
        defer { CompilationConditions.isSDKCompiledForDevelopment = originalValue }
        var printedMessage: String?

        CompilationConditions.isSDKCompiledForDevelopment = true

        let developerLogger = createSDKDeveloperLogger(
            consolePrintFunction: { printedMessage = $0 },
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        developerLogger?.info("It works.")

        XCTAssertNotNil(developerLogger)
        XCTAssertEqual(printedMessage, "🐶 → 10:00:00.000Z [INFO] It works.")
    }
}
