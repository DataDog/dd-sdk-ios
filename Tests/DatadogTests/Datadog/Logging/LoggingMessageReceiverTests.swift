/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class LoggingMessageReceiverTests: XCTestCase {
    func testReceiveIncompleteLogMessage() throws {
        let expectation = expectation(description: "Don't send log fallback")

        // Given
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
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
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
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
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
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
        XCTAssertEqual(
            log.attributes.userAttributes as? [String: String],
            ["user": "attribute"]
        )
        XCTAssertEqual(
            log.attributes.internalAttributes as? [String: String],
            ["internal": "attribute"]
        )
        XCTAssertNotNil(log.networkConnectionInfo)
    }

    func testReceiveRejectedLogMessage() throws {
        // Given
        let core = PassthroughCoreMock(
            context: .mockWith(service: "service-test"),
            expectation: expectation(description: "Open scope but don't send log"),
            messageReceiver: LoggingMessageReceiver(logEventMapper: SyncLogEventMapper { _ in nil })
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

    func testReceiveEvent() throws {
        // Given
        struct Event: Encodable {
            let test: String
        }

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Event"),
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
        )

        // When
        let value: String = .mockRandom()

        core.send(
            message: .custom(key: LoggingMessageKeys.browserLog, baggage: .init([
                "test": value
            ]))
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let received: AnyEncodable = try XCTUnwrap(core.events().last, "It should send event")
        let expected: [String: Any] = [
            "ddtags": "version:abc,env:abc",
            "test": value
        ]

        try AssertEncodedRepresentationsEqual(received, AnyEncodable(expected))
    }

    func testReceiveCrashLog() throws {
        // Given
        let core = PassthroughCoreMock(
            bypassConsentExpectation: expectation(description: "Send Event Bypass Consent"),
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
        )

        // When
        let sent: LogEvent = .mockRandom()

        core.send(
            message: .custom(key: LoggingMessageKeys.crash, baggage: [
                "log": sent
            ])
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let received: LogEvent = try XCTUnwrap(core.events().last, "It should send event")
        try AssertEncodedRepresentationsEqual(received, sent)
    }

    // MARK: - Web-view log

    func testWhenValidWebLogEventPassed_itDecoratesAndPassesToWriter() throws {
        let applicationVersion: String = .mockRandom()
        let environment: String = .mockRandom()
        let mockSessionID: UUID = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                env: environment,
                version: applicationVersion,
                serverTimeOffset: 123,
                featuresAttributes: [
                    "rum": [
                        RUMContextAttributes.applicationID: "123456",
                        RUMContextAttributes.sessionID: mockSessionID.uuidString.lowercased()
                    ]
                ]
            ),
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
        )

        let webLogEvent: JSON = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        let expectedWebLogEvent: JSON = [
            "date": 1_635_932_927_012 + 123.toInt64Milliseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "version:\(applicationVersion),env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        core.send(
            message: .custom(
                key: LoggingMessageKeys.browserLog,
                baggage: .init(webLogEvent)
            )
        )

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)
    }

    func testWhenContextIsUnavailable_itPassesWebviewEventAsIs() throws {
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                env: environment,
                version: applicationVersion
            ),
            messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
        )

        let webLogEvent: JSON = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        var expectedWebLogEvent: JSON = webLogEvent
        expectedWebLogEvent["ddtags"] = "version:\(applicationVersion),env:\(environment)"

        core.send(
            message: .custom(
                key: LoggingMessageKeys.browserLog,
                baggage: .init(webLogEvent)
            )
        )

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)
    }
}
