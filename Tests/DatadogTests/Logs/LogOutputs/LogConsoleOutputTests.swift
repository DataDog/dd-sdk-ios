import XCTest
@testable import Datadog

class LogConsoleOutputTests: XCTestCase {
    func testItPrintsLogUsingPrintingFunction() {
        var messagePrinted: String = ""

        let output = LogConsoleOutput { message in
            messagePrinted = message
        }

        let log: Log = .mockRandom()
        output.write(log: log)

        XCTAssertTrue(messagePrinted != "")
    }
}
