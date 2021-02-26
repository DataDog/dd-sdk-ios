/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets trailing_closure
class LogConsoleOutputTests: XCTestCase {
    private let log: Log = .mockWith(date: .mockDecember15th2019At10AMUTC(), status: .info, message: "Info message.")

    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            format: .short,
            timeZone: .UTC,
            printingFunction: { messagePrinted = $0 }
        )
        output1.write(log: log)
        XCTAssertEqual(messagePrinted, "10:00:00.000 [INFO] Info message.")

        let output2 = LogConsoleOutput(
            format: .shortWith(prefix: "🐶 "),
            timeZone: .UTC,
            printingFunction: { messagePrinted = $0 }
        )
        output2.write(log: log)
        XCTAssertEqual(messagePrinted, "🐶 10:00:00.000 [INFO] Info message.")
    }

    func testWhenUsingShortFormat_itFormatsTimeInCurrentTimeZone() {
        var messagePrinted: String = ""

        let output = LogConsoleOutput(
            format: .short,
            timeZone: .EET,
            printingFunction: { messagePrinted = $0 }
        )
        output.write(log: log)
        XCTAssertEqual(messagePrinted, "12:00:00.000 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() throws {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            format: .json,
            timeZone: .mockAny(),
            printingFunction: { messagePrinted = $0 }
        )
        output1.write(log: log)
        try LogMatcher.fromJSONObjectData(messagePrinted.utf8Data)
            .assertMessage(equals: "Info message.")

        let output2 = LogConsoleOutput(
            format: .jsonWith(prefix: "🐶 → "),
            timeZone: .mockAny(),
            printingFunction: { messagePrinted = $0 }
        )
        output2.write(log: log)
        XCTAssertTrue(messagePrinted.hasPrefix("🐶 → "))
        try LogMatcher.fromJSONObjectData(messagePrinted.removingPrefix("🐶 → ").utf8Data)
            .assertMessage(equals: "Info message.")
    }
}
