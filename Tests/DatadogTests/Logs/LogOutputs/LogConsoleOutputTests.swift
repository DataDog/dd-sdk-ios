import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets trailing_closure
class LogConsoleOutputTests: XCTestCase {
    private let logBuilder: LogBuilder = .mockUsing(
        date: .mockDecember15th2019At10AMUTC(),
        serviceName: "test-service"
    )

    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .short,
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:])
        XCTAssertEqual(messagePrinted, "10:00:00 [INFO] Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .shortWith(prefix: "🐶 "),
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:])
        XCTAssertEqual(messagePrinted, "🐶 10:00:00 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .json,
            printingFunction: { messagePrinted = $0 }
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:])
        XCTAssertEqual(messagePrinted, """
        {
          "status" : "INFO",
          "message" : "Info message.",
          "service" : "test-service",
          "date" : "2019-12-15T10:00:00Z"
        }
        """)

        let output2 = LogConsoleOutput(
            logBuilder: logBuilder,
            format: .jsonWith(prefix: "🐶 → "),
            printingFunction: { messagePrinted = $0 }
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:])
        XCTAssertEqual(messagePrinted, """
        🐶 → {
          "status" : "INFO",
          "message" : "Info message.",
          "service" : "test-service",
          "date" : "2019-12-15T10:00:00Z"
        }
        """)
    }
}
