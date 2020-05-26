/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingToLoggingOutputTests: XCTestCase {
    private typealias OTFields = TracingToLoggingOutput.OpenTracingFields
    private typealias DDFields = TracingToLoggingOutput.DatadogFields
    private typealias DefaultValues = TracingToLoggingOutput.DefaultFieldValues

    func testLoggingMessageWithStandardOTFields() {
        let loggingOutput = LogOutputMock()
        let tracingOutput = TracingToLoggingOutput(loggingOutput: loggingOutput)

        tracingOutput.writeLogWith(
            spanContext: .mockWith(
                traceID: 1,
                spanID: 2
            ),
            fields: [
                OTFields.message: "hello",
                "custom field": 123,
            ],
            date: .mockDecember15th2019At10AMUTC()
        )

        let expectedLog = LogOutputMock.RecordedLog(
            level: .info,
            message: "hello", // `OTFields.message` value is used as the log message.
            date: .mockDecember15th2019At10AMUTC(),
            attributes: [
                "custom field": 123,
                DDFields.spanID: "2",
                DDFields.traceID: "1"
                // `OTFields.message` does not appear as the attribute.
            ]
        )

        XCTAssertEqual(loggingOutput.recordedLog, expectedLog)
    }

    func testLoggingMessageWithoutStandardOTFields() {
        let loggingOutput = LogOutputMock()
        let tracingOutput = TracingToLoggingOutput(loggingOutput: loggingOutput)

        tracingOutput.writeLogWith(
            spanContext: .mockWith(
                traceID: 1,
                spanID: 2
            ),
            fields: ["custom field": 123],
            date: .mockDecember15th2019At10AMUTC()
        )

        let expectedLog = LogOutputMock.RecordedLog(
            level: .info,
            message: DefaultValues.message, // Default message is used.
            date: .mockDecember15th2019At10AMUTC(),
            attributes: [
                "custom field": 123,
                DDFields.spanID: "2",
                DDFields.traceID: "1"
            ]
        )

        XCTAssertEqual(loggingOutput.recordedLog, expectedLog)
    }
}
