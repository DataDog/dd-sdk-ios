/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogLogs

class LogMessageReceiverTests: XCTestCase {
    struct LogMessage: Encodable {
        let logger: String
        let service: String?
        let date: Date
        let message: String
        let level: LogLevel
        let thread: String
        let error: DDError?
        let networkInfoEnabled: Bool?
        let userAttributes: [String: String]?
        let internalAttributes: [String: String]?
    }

    func testReceiveIncompleteLogMessage() throws {
        let expectation = expectation(description: "Don't send log fallback")

        // Given
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            messageReceiver: LogMessageReceiver.mockAny()
        )

        // When
        core.send(
            message: .baggage(
                key: "log",
                value: "wrong-type"
            ),
            else: { expectation.fulfill() }
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testReceivePartialLogMessage() throws {
        // Given
        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        core.send(
            message: .baggage(
                key: "log",
                value: LogMessage(
                    logger: "logger-test",
                    service: nil,
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    level: .info,
                    thread: "thread-test",
                    error: nil,
                    networkInfoEnabled: nil,
                    userAttributes: nil,
                    internalAttributes: nil
                )
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.loggerName, "logger-test")
        XCTAssertEqual(log.serviceName, "service-test")
        XCTAssertEqual(log.threadName, "thread-test")
        XCTAssertEqual(log.message, "message-test")
        XCTAssertEqual(log.status, .info)
        XCTAssertNil(log.error)
        XCTAssertTrue(log.attributes.userAttributes.isEmpty)
        XCTAssertNil(log.attributes.internalAttributes)
        XCTAssertNil(log.networkConnectionInfo)
    }

    func testReceiveCompleteLogMessage() throws {
        // Given
        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockAny(),
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        core.send(
            message: .baggage(
                key: "log",
                value: LogMessage(
                    logger: "logger-test",
                    service: "service-test",
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    level: .info,
                    thread: "thread-test",
                    error: .mockAny(),
                    networkInfoEnabled: true,
                    userAttributes: ["user": "attribute"],
                    internalAttributes: ["internal": "attribute"]
                )
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.loggerName, "logger-test")
        XCTAssertEqual(log.serviceName, "service-test")
        XCTAssertEqual(log.threadName, "thread-test")
        XCTAssertEqual(log.message, "message-test")
        XCTAssertEqual(log.status, .info)
        XCTAssertEqual(log.error?.message, "abc")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes),
            ["user": "attribute"]
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes),
            ["internal": "attribute"]
        )
        XCTAssertNotNil(log.networkConnectionInfo)
    }

    func testReceiveRejectedLogMessage() throws {
        // Given
        let expectation = expectation(description: "Open scope but don't send log")
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            messageReceiver: LogMessageReceiver(
                logEventMapper: SyncLogEventMapper { _ in nil }
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        core.send(
            message: .baggage(
                key: "log",
                value: LogMessage(
                    logger: "logger-test",
                    service: nil,
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    level: .info,
                    thread: "thread-test",
                    error: nil,
                    networkInfoEnabled: nil,
                    userAttributes: nil,
                    internalAttributes: nil
                )
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }
}
