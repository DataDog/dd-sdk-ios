/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDSpanTests: XCTestCase {
    func testOverwritingOperationName() {
        let span = DDSpan(
            tracer: .mockNoOp(),
            operationName: "initial",
            parentSpanContext: nil,
            startTime: .mockAny()
        )
        span.setOperationName("new")
        XCTAssertEqual(span.operationName, "new")
    }

    func testGivenFinishedSpan_whenAttemptingToFinishItAgain_itPrintsError() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, identifier: "sdk-user")

        let span = DDSpan(
            tracer: .mockNoOp(),
            operationName: "the span",
            parentSpanContext: nil,
            startTime: .mockAny()
        )
        span.finish()
        span.finish()

        XCTAssertEqual(output.recordedLog?.level, .error)
        XCTAssertEqual(
            output.recordedLog?.message,
            "🔥 Failed to finish the span: Attempted to finish already finished span: \"the span\"."
        )
    }
}
