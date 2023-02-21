/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogLogs

class LogFileOutputTests: XCTestCase {
    func testItWritesLogs() throws {
        let writer = FileWriterMock()
        let output = LogFileOutput(fileWriter: writer)

        output.write(log: .mockWith(status: .info, message: "log message 1"))
        output.write(log: .mockWith(status: .warn, message: "log message 2"))

        let logs: [LogEvent] = writer.events()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].status, .info)
        XCTAssertEqual(logs[0].message, "log message 1")
        XCTAssertEqual(logs[1].status, .warn)
        XCTAssertEqual(logs[1].message, "log message 2")
    }
}
