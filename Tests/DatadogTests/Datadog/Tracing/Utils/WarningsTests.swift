/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class WarningsTests: XCTestCase {
    func testPrintingWarningsOnDifferentConditions() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output, dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()))

        XCTAssertTrue(warn(if: true, message: "message"))
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(output.recordedLog?.message, "message")
        XCTAssertEqual(output.recordedLog?.date, .mockDecember15th2019At10AMUTC())

        output.recordedLog = nil

        XCTAssertFalse(warn(if: false, message: "message"))
        XCTAssertNil(output.recordedLog)

        output.recordedLog = nil

        let failingCast: () -> DDSpan? = { warnIfCannotCast(value: DDNoopSpan()) }
        XCTAssertNil(failingCast())
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Using DDNoopSpan while DDSpan was expected.")
        XCTAssertEqual(output.recordedLog?.date, .mockDecember15th2019At10AMUTC())

        output.recordedLog = nil

        let succeedingCast: () -> DDSpan? = { warnIfCannotCast(value: DDSpan.mockAny()) }
        XCTAssertNotNil(succeedingCast())
        XCTAssertNil(output.recordedLog)
    }
}
