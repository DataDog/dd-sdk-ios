import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets trailing_closure
class LogConsoleOutputTests: XCTestCase {
    private let logBuilder = LogBuilder(
        appContext: .mockWith(
            bundleIdentifier: "com.datadoghq.ios-sdk",
            bundleVersion: "1.0.0",
            bundleShortVersion: "1.0.0"
        ),
        serviceName: "test-service",
        loggerName: "test-logger-name",
        dateProvider: RelativeDateProvider(
            using: .mockDecember15th2019At10AMUTC()
        ),
        userInfoProvider: .mockWith(userInfo: .mockEmpty()),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes,
                availableInterfaces: [.wifi, .cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: false,
                isConstrained: false
            )
        ),
        carrierInfoProvider: nil
    )

    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .short,
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "10:00:00 [INFO] Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .shortWith(prefix: "🐶 "),
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "🐶 10:00:00 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() throws {
        var messagePrinted: String = ""
        let expectedMessageJSON = """
        {
          "status" : "INFO",
          "message" : "Info message.",
          "service" : "test-service",
          "logger.name" : "test-logger-name",
          "logger.version": "\(sdkVersion)",
          "logger.thread_name" : "main",
          "date" : "2019-12-15T10:00:00Z",
          "application.version": "1.0.0"
        }
        """

        let output1 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .json,
            printingFunction: { messagePrinted = $0 }
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        try LogMatcher(from: messagePrinted.utf8Data)
            .assertItFullyMatches(jsonString: expectedMessageJSON)

        let output2 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .jsonWith(prefix: "🐶 → "),
            printingFunction: { messagePrinted = $0 }
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertTrue(messagePrinted.hasPrefix("🐶 → "))
        try LogMatcher(from: messagePrinted.removingPrefix("🐶 → ").utf8Data)
            .assertItFullyMatches(jsonString: expectedMessageJSON)
    }
}
