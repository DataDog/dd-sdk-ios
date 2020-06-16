/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets trailing_closure
class LogConsoleOutputTests: XCTestCase {
    func testItPrintsLogsUsingShortFormat() {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .short,
            timeZone: .UTC,
            printingFunction: { messagePrinted = $0 }
        )
        output1.writeLogWith(level: .info, message: "Info message.", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "10:00:00.000 [INFO] Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .shortWith(prefix: "🐶 "),
            timeZone: .UTC,
            printingFunction: { messagePrinted = $0 }
        )
        output2.writeLogWith(level: .info, message: "Info message.", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "🐶 10:00:00.000 [INFO] Info message.")
    }

    func testWhenUsingShortFormat_itFormatsTimeInCurrentTimeZone() {
        var messagePrinted: String = ""

        let output = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .short,
            timeZone: .EET,
            printingFunction: { messagePrinted = $0 }
        )
        output.writeLogWith(level: .info, message: "Info message.", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        XCTAssertEqual(messagePrinted, "12:00:00.000 [INFO] Info message.")
    }

    func testItPrintsLogsUsingJSONFormat() throws {
        var messagePrinted: String = ""

        let output1 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .json,
            timeZone: .mockAny(),
            printingFunction: { messagePrinted = $0 }
        )
        output1.writeLogWith(level: .info, message: "Info message.", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        try LogMatcher.fromJSONObjectData(messagePrinted.utf8Data)
            .assertMessage(equals: "Info message.")

        let output2 = LogConsoleOutput(
            logBuilder: .mockAny(),
            format: .jsonWith(prefix: "🐶 → "),
            timeZone: .mockAny(),
            printingFunction: { messagePrinted = $0 }
        )
        output2.writeLogWith(level: .info, message: "Info message.", date: .mockDecember15th2019At10AMUTC(), attributes: [:], tags: [])
        XCTAssertTrue(messagePrinted.hasPrefix("🐶 → "))
        try LogMatcher.fromJSONObjectData(messagePrinted.removingPrefix("🐶 → ").utf8Data)
            .assertMessage(equals: "Info message.")
    }
}
