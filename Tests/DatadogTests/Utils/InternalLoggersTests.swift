import XCTest
@testable import Datadog

class DeveloperLoggerTests: XCTestCase {
    func testWhenCompiledNotForDevelopment_itIsNotAvailable() {
        let originalValue = CompilationConditions.isSDKCompiledForDevelopment
        defer { CompilationConditions.isSDKCompiledForDevelopment = originalValue }

        CompilationConditions.isSDKCompiledForDevelopment = false

        XCTAssertNil(createSDKDeveloperLogger())
    }

    func testWhenCompiledForDevelopment_itIsAvailable() {
        let originalValue = CompilationConditions.isSDKCompiledForDevelopment
        defer { CompilationConditions.isSDKCompiledForDevelopment = originalValue }
        var printedMessage: String?

        CompilationConditions.isSDKCompiledForDevelopment = true

        let developerLogger = createSDKDeveloperLogger(
            consolePrintFunction: { printedMessage = $0 },
            dateProvider: DateProviderMock.mockReturning(currentDate: .mockDecember15th2019At10AMUTC())
        )
        developerLogger?.info("It works.")

        XCTAssertNotNil(developerLogger)
        XCTAssertEqual(printedMessage, "🐶 → 2019-12-15 10:00:00 +0000 [INFO] It works.")
    }
}

class UserLoggerTests: XCTestCase {
    private var printedMessages: [String]! // swiftlint:disable:this implicitly_unwrapped_optional
    private var userLogger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        printedMessages = []
        userLogger = createSDKUserLogger(
            consolePrintFunction: { [weak self] in self?.printedMessages.append($0) },
            dateProvider: DateProviderMock.mockReturning(currentDate: .mockDecember15th2019At10AMUTC())
        )
    }

    override func tearDown() {
        printedMessages = nil
        userLogger = nil
        super.tearDown()
    }

    private func logMessageUsingAllLevels(_ message: String) {
        userLogger.debug(message)
        userLogger.info(message)
        userLogger.notice(message)
        userLogger.warn(message)
        userLogger.error(message)
        userLogger.critical(message)
    }

    private let expectedMessages = [
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [DEBUG] message",
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [INFO] message",
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [NOTICE] message",
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [WARN] message",
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [ERROR] message",
        "[DATADOG SDK] 🐶 → 2019-12-15 10:00:00 +0000 [CRITICAL] message"
    ]

    func testItDoesNothingWithDefaultVerbosityLevel() {
        XCTAssertNil(Datadog.verbosityLevel)
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, [])
    }

    func testItPrintsWithVerbosityLevel_debug() {
        Datadog.verbosityLevel = .debug
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[0..<expectedMessages.count]))
    }

    func testItPrintsWithVerbosityLevel_info() {
        Datadog.verbosityLevel = .info
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[1..<expectedMessages.count]))
    }

    func testItPrintsWithVerbosityLevel_notice() {
        Datadog.verbosityLevel = .notice
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[2..<expectedMessages.count]))
    }

    func testItPrintsWithVerbosityLevel_warn() {
        Datadog.verbosityLevel = .warn
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[3..<expectedMessages.count]))
    }

    func testItPrintsWithVerbosityLevel_error() {
        Datadog.verbosityLevel = .error
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[4..<expectedMessages.count]))
    }

    func testItPrintsWithVerbosityLevel_critical() {
        Datadog.verbosityLevel = .critical
        logMessageUsingAllLevels("message")
        XCTAssertEqual(printedMessages, Array(expectedMessages[5..<expectedMessages.count]))
    }
}
