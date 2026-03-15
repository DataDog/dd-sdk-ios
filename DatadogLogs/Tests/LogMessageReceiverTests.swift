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
    func testReceivePartialLogMessage() async throws {
        // Given
        let core = PassthroughCoreMock(context: .mockWith(service: "service-test"))
        core.messageReceiver = LogMessageReceiver.mockWith(featureScope: core)

        // When
        core.send(
            message: .payload(
                LogMessage(
                    logger: "logger-test",
                    service: nil,
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    error: nil,
                    level: .info,
                    thread: "thread-test",
                    networkInfoEnabled: nil,
                    userAttributes: nil,
                    internalAttributes: nil
                )
            )
        )

        // Then
        await core.writer.waitForEvents(count: 1)

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

    func testReceiveCompleteLogMessage() async throws {
        // Given
        let core = PassthroughCoreMock(context: .mockAny())
        core.messageReceiver = LogMessageReceiver.mockWith(featureScope: core)

        // When
        core.send(
            message: .payload(
                LogMessage(
                    logger: "logger-test",
                    service: "service-test",
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    error: .mockAny(),
                    level: .info,
                    thread: "thread-test",
                    networkInfoEnabled: true,
                    userAttributes: ["user": "attribute"],
                    internalAttributes: ["internal": "attribute"]
                )
            )
        )

        // Then
        await core.writer.waitForEvents(count: 1)

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

    func testReceiveRejectedLogMessage() async throws {
        // Given
        let core = PassthroughCoreMock(context: .mockWith(service: "service-test"))
        core.messageReceiver = LogMessageReceiver(
            logEventMapper: SyncLogEventMapper { _ in nil },
            featureScope: core
        )

        // When
        core.send(
            message: .payload(
                LogMessage(
                    logger: "logger-test",
                    service: nil,
                    date: .mockDecember15th2019At10AMUTC(),
                    message: "message-test",
                    error: nil,
                    level: .info,
                    thread: "thread-test",
                    networkInfoEnabled: nil,
                    userAttributes: nil,
                    internalAttributes: nil
                )
            )
        )

        // Then — the mapper drops the event, so nothing should be written
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(core.events.isEmpty)
    }
}
