/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogLogs
@testable import DatadogTrace
@testable import DatadogCore

class TracingWithLoggingIntegrationTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(messageReceiver: LogMessageReceiver.mockAny())
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testSendingLogWithOTMessageField() throws {
        let expectation = expectation(description: "Send log")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let integration = TracingWithLoggingIntegration(core: core, service: .mockAny(), networkInfoEnabled: .mockAny())

        // When
        integration.writeLog(
            withSpanContext: .mockWith(traceID: .init(idHi: 10, idLo: 100), spanID: 200),
            fields: [
                OTLogFields.message: "hello",
                "custom field": 123,
            ],
            date: .mockDecember15th2019At10AMUTC(),
            else: {}
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.status, .info)
        XCTAssertEqual(log.message, "hello")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes),
            AnyEncodable(["custom field": 123])
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes),
            AnyEncodable([
                "dd.trace_id": "a0000000000000064",
                "dd.span_id": "c8"
            ])
        )
    }

    func testWritingLogWithOTErrorField() throws {
        let expectation = expectation(description: "Send 3 logs")
        expectation.expectedFulfillmentCount = 3
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let integration = TracingWithLoggingIntegration(core: core, service: .mockAny(), networkInfoEnabled: .mockAny())

        // When
        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error"],
            date: .mockAny(),
            else: {}
        )

        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.errorKind: "Swift error"],
            date: .mockAny(),
            else: {}
        )

        integration.writeLog(
            withSpanContext: .mockAny(),
            fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error"],
            date: .mockAny(),
            else: {}
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs: [LogEvent] = try XCTUnwrap(core.events())
        XCTAssertEqual(logs.count, 3, "It should send 3 logs")
        logs.forEach { log in
            XCTAssertEqual(log.status, .error)
            XCTAssertEqual(log.message, "Span event")
        }
    }

    func testWritingCustomLogWithoutAnyOTFields() throws {
        let expectation = expectation(description: "Send log")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let integration = TracingWithLoggingIntegration(core: core, service: .mockAny(), networkInfoEnabled: .mockAny())

        // When
        integration.writeLog(
            withSpanContext: .mockWith(traceID: .init(idHi: 10, idLo: 100), spanID: 200),
            fields: ["custom field": 123],
            date: .mockDecember15th2019At10AMUTC(),
            else: {}
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.status, .info)
        XCTAssertEqual(log.message, "Span event", "It should use default message.")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes),
            AnyEncodable(["custom field": 123])
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes),
            AnyEncodable([
                "dd.trace_id": "a0000000000000064",
                "dd.span_id": "c8"
            ])
        )
    }
}
