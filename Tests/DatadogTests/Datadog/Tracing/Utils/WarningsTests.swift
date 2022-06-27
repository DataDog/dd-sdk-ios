/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class WarningsTests: XCTestCase {
    func testPrintingWarningsOnDifferentConditions() {
        let core = DatadogCoreMock()
        core.register(feature: LoggingFeature.mockNoOp())
        defer { core.flush() }

        let (old, logger) = dd.replacing(logger: CoreLoggerMock())
        defer { dd = old }

        XCTAssertTrue(warn(if: true, message: "message"))
        XCTAssertEqual(logger.warnLog?.message, "message")

        logger.reset()

        XCTAssertFalse(warn(if: false, message: "message"))
        XCTAssertNil(logger.warnLog)

        logger.reset()

        let failingCast: () -> DDSpan? = { warnIfCannotCast(value: DDNoopSpan()) }
        XCTAssertNil(failingCast())
        XCTAssertEqual(logger.warnLog?.message, "🔥 Using DDNoopSpan while DDSpan was expected.")

        logger.reset()

        let succeedingCast: () -> DDSpan? = { warnIfCannotCast(value: DDSpan.mockAny(in: core)) }
        XCTAssertNotNil(succeedingCast())
        XCTAssertNil(logger.warnLog)
    }
}
