/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingWithLoggingIntegrationTests: XCTestCase {
    func testWritingLogWithOTMessageField() throws {
        let loggingOutput = LogOutputMock()
        let integration = TracingWithLoggingIntegration(
            logBuilder: .mockAny(),
            loggingOutput: loggingOutput
        )

        integration.writeLog(
            withSpanContext: .mockWith(traceID: 1, spanID: 2),
            fields: [
                OTLogFields.message: "hello",
                "custom field": 123,
            ],
            date: .mockDecember15th2019At10AMUTC()
        )

        let recordedLog = try XCTUnwrap(loggingOutput.recordedLog)
        XCTAssertEqual(recordedLog.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(recordedLog.status, .info)
        XCTAssertEqual(recordedLog.message, "hello")
        XCTAssertEqual(
            recordedLog.attributes.userAttributes as? [String: Int],
            ["custom field": 123]
        )
        XCTAssertEqual(
            recordedLog.attributes.internalAttributes as? [String: String],
            [
                "dd.span_id": "2",
                "dd.trace_id": "1"
            ]
        )
    }

    func testWritingLogWithOTErrorField() throws {
        let loggingOutput = LogOutputMock()
        let integration = TracingWithLoggingIntegration(
            logBuilder: .mockAny(),
            loggingOutput: loggingOutput
        )

        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error"],
            date: .mockAny()
        )

        let recordedLog1 = try XCTUnwrap(loggingOutput.recordedLog)

        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.errorKind: "Swift error"],
            date: .mockAny()
        )

        let recordedLog2 = try XCTUnwrap(loggingOutput.recordedLog)

        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error"],
            date: .mockAny()
        )

        let recordedLog3 = try XCTUnwrap(loggingOutput.recordedLog)

        [recordedLog1, recordedLog2, recordedLog3].forEach { log in
            XCTAssertEqual(log.status, .error)
            XCTAssertEqual(log.message, "Span event")
        }
    }

    func testWritingCustomLogWithoutAnyOTFields() throws {
        let loggingOutput = LogOutputMock()
        let integration = TracingWithLoggingIntegration(
            logBuilder: .mockAny(),
            loggingOutput: loggingOutput
        )

        integration.writeLog(
            withSpanContext: .mockWith(traceID: 1, spanID: 2),
            fields: ["custom field": 123],
            date: .mockDecember15th2019At10AMUTC()
        )

        let recordedLog = try XCTUnwrap(loggingOutput.recordedLog)
        XCTAssertEqual(recordedLog.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(recordedLog.status, .info)
        XCTAssertEqual(recordedLog.message, "Span event", "It should use default message.")
        XCTAssertEqual(
            recordedLog.attributes.userAttributes as? [String: Int],
            ["custom field": 123]
        )
        XCTAssertEqual(
            recordedLog.attributes.internalAttributes as? [String: String],
            [
                "dd.span_id": "2",
                "dd.trace_id": "1"
            ]
        )
    }
}
