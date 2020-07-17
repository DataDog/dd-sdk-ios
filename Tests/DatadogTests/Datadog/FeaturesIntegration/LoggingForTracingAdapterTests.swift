/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggingForTracingAdapterTests: XCTestCase {
    // MARK: - LoggingForTracingAdapter.AdaptedLogOutput

    func testWritingLogWithOTMessageField() {
        let loggingOutput = LogOutputMock()
        let tracingOutput = LoggingForTracingAdapter.AdaptedLogOutput(loggingOutput: loggingOutput)

        tracingOutput.writeLog(
            withSpanContext: .mockWith(traceID: 1, spanID: 2),
            fields: [
                OTLogFields.message: "hello",
                "custom field": 123,
            ],
            date: .mockDecember15th2019At10AMUTC()
        )

        let expectedLog = LogOutputMock.RecordedLog(
            level: .info,
            message: "hello",
            date: .mockDecember15th2019At10AMUTC(),
            attributes: LogAttributes(
                userAttributes: [
                    "custom field": 123,
                ],
                internalAttributes: [
                    "dd.span_id": "2",
                    "dd.trace_id": "1"
                ]
            )
        )

        XCTAssertEqual(loggingOutput.recordedLog, expectedLog)
    }

    func testWritingLogWithOTErrorField() {
        let loggingOutput = LogOutputMock()
        let tracingOutput = LoggingForTracingAdapter.AdaptedLogOutput(loggingOutput: loggingOutput)

        tracingOutput.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error"],
            date: .mockAny()
        )

        let recordedLog1 = loggingOutput.recordedLog

        tracingOutput.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.errorKind: "Swift error"],
            date: .mockAny()
        )

        let recordedLog2 = loggingOutput.recordedLog

        tracingOutput.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error"],
            date: .mockAny()
        )

        let recordedLog3 = loggingOutput.recordedLog

        [recordedLog1, recordedLog2, recordedLog3].forEach { log in
            XCTAssertEqual(log?.level, .error)
            XCTAssertEqual(log?.message, "Span event")
        }
    }

    func testWritingCustomLogWithoutAnyOTFields() {
        let loggingOutput = LogOutputMock()
        let tracingOutput = LoggingForTracingAdapter.AdaptedLogOutput(loggingOutput: loggingOutput)

        tracingOutput.writeLog(
            withSpanContext: .mockWith(traceID: 1, spanID: 2),
            fields: ["custom field": 123],
            date: .mockDecember15th2019At10AMUTC()
        )

        let expectedLog = LogOutputMock.RecordedLog(
            level: .info,
            message: "Span event", // default message is used.
            date: .mockDecember15th2019At10AMUTC(),
            attributes: LogAttributes(
                userAttributes: [
                    "custom field": 123,
                ],
                internalAttributes: [
                    "dd.span_id": "2",
                    "dd.trace_id": "1"
                ]
            )
        )

        XCTAssertEqual(loggingOutput.recordedLog, expectedLog)
    }
}
