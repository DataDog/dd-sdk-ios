import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets trailing_closure
class LogConsoleOutputTests: XCTestCase {
    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: .mockWith(date: .mockDecember15th2019At10AMUTC()),
            format: .short,
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "10:00:00 [INFO] Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: .mockWith(date: .mockDecember15th2019At10AMUTC()),
            format: .shortWith(prefix: "🐶 "),
            printingFunction: { messagePrinted = $0 },
            timeFormatter: LogConsoleOutput.shortTimeFormatter(calendar: .gregorian, timeZone: .UTC)
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "🐶 10:00:00 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() throws {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .json,
            printingFunction: { messagePrinted = $0 }
        )
        output1.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        try LogMatcher(from: messagePrinted.utf8Data)
            .assertMessage(equals: "Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .jsonWith(prefix: "🐶 → "),
            printingFunction: { messagePrinted = $0 }
        )
        output2.writeLogWith(level: .info, message: "Info message.", attributes: [:], tags: [])
        XCTAssertTrue(messagePrinted.hasPrefix("🐶 → "))
        try LogMatcher(from: messagePrinted.removingPrefix("🐶 → ").utf8Data)
            .assertMessage(equals: "Info message.")
    }
}
