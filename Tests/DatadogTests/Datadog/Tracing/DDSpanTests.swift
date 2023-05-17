/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogTrace

class DDSpanTests: XCTestCase {
    // MARK: - Sending Span Logs

    func testWhenLoggingSpanEvent_itWritesLogToLogOutput() throws {
        let core = PassthroughCoreMock(
            messageReceiver: LogMessageReceiver.mockAny()
        )

        core.expectation = expectation(description: "write span event")
        core.expectation?.expectedFulfillmentCount = 2

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span: DDSpan = .mockWith(tracer: tracer)

        // When
        let log1Fields = mockRandomAttributes()
        span.log(fields: log1Fields)

        let log2Fields = mockRandomAttributes()
        span.log(fields: log2Fields)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs: [LogEvent] = core.events()
        XCTAssertEqual(logs.count, 2, "It should send 2 logs")
        DDAssertJSONEqual(
            AnyEncodable(logs[0].attributes.userAttributes),
            AnyEncodable(log1Fields)
        )
        DDAssertJSONEqual(
            AnyEncodable(logs[1].attributes.userAttributes),
            AnyEncodable(log2Fields)
        )
    }
}
