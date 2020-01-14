import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LogConsoleOutputTests: XCTestCase {
    private let log = Log(
        date: .mockDecember15th2019At10AMUTC(),
        status: .info,
        message: "Info message.",
        service: "test-service"
    )

    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(format: .short) { messagePrinted = $0 }
        output1.write(log: log)
        XCTAssertEqual(messagePrinted, "2019-12-15 10:00:00 +0000 [INFO] Info message.")

        let output2 = LogConsoleOutput(format: .shortWith(prefix: "🐶 ")) { messagePrinted = $0 }
        output2.write(log: log)
        XCTAssertEqual(messagePrinted, "🐶 2019-12-15 10:00:00 +0000 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(format: .json) { messagePrinted = $0 }
        output1.write(log: log)
        XCTAssertEqual(messagePrinted, """
        {
          "status" : "INFO",
          "message" : "Info message.",
          "service" : "test-service",
          "date" : "2019-12-15T10:00:00Z"
        }
        """)

        let output2 = LogConsoleOutput(format: .jsonWith(prefix: "🐶 → ")) { messagePrinted = $0 }
        output2.write(log: log)
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
