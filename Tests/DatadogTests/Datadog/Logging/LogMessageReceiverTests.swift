/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class LogMessageReceiverTests: XCTestCase {
    func testReceiveIncompleteLogMessage() throws {
        let expectation = expectation(description: "Don't send log fallback")

        // Given
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            messageReceiver: LogMessageReceiver.mockAny()
        )

        // When
        core.send(
            message: .custom(
                key: "log",
                baggage: [
                    "date": Date.mockDecember15th2019At10AMUTC(),
                    "message": "message-test",
                ]
            ),
            else: { expectation.fulfill() }
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testReceivePartialLogMessage() throws {
        // Given
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            expectation: expectation(description: "Send log"),
            messageReceiver: LogMessageReceiver.mockAny()
        )

        // When
        core.send(
            message: .custom(
                key: "log",
                baggage: [
                    "date": Date.mockDecember15th2019At10AMUTC(),
                    "loggerName": "logger-test",
                    "threadName": "thread-test",
                    "message": "message-test",
                    "level": LogLevel.info
                ]
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
        let core = PassthroughCoreMock(
            context: .mockAny(),
            expectation: expectation(description: "Send log"),
            messageReceiver: LogMessageReceiver.mockAny()
        )

        // When
        core.send(
            message: .custom(
                key: "log",
                baggage: [
                    "date": Date.mockDecember15th2019At10AMUTC(),
                    "loggerName": "logger-test",
                    "service": "service-test",
                    "threadName": "thread-test",
                    "message": "message-test",
                    "level": LogLevel.info,
                    "error": DDError.mockAny(),
                    "userAttributes": ["user": "attribute"],
                    "internalAttributes": ["internal": "attribute"],
                    "sendNetworkInfo": true
                ]
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
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            expectation: expectation(description: "Open scope but don't send log"),
            messageReceiver: LogMessageReceiver(
                logEventMapper: SyncLogEventMapper { _ in nil }
            )
        )

        // When
        core.send(
            message: .custom(
                key: "log",
                baggage: [
                    "date": Date.mockDecember15th2019At10AMUTC(),
                    "loggerName": "logger-test",
                    "threadName": "thread-test",
                    "message": "message-test",
                    "level": LogLevel.info
                ]
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }
}
