/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs

class WebViewLogReceiverTests: XCTestCase {
    func testReceiveEvent() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Event")
        )

        // When
        let value: String = .mockRandom()

        XCTAssert(
            messageReceiver.receive(
                message: .baggage(
                    key: LoggingMessageKeys.browserLog,
                    value: AnyEncodable([ "test": value ])
                ),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let received: AnyEncodable = try XCTUnwrap(core.events().last, "It should send event")
        let expected: [String: Any] = [
            "ddtags": "version:abc,env:abc",
            "test": value
        ]

        DDAssertJSONEqual(received, AnyEncodable(expected))
    }

    // MARK: - Web-view log

    func testWhenValidWebLogEventPassed_itDecoratesAndPassesToWriter() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let applicationVersion: String = .mockRandom()
        let environment: String = .mockRandom()
        let mockSessionID: UUID = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                env: environment,
                version: applicationVersion,
                serverTimeOffset: 123,
                baggages: [
                    "rum": .init([
                        "application.id": "123456",
                        "session.id": mockSessionID.uuidString.lowercased()
                    ])
                ]
            )
        )

        let webLogEvent: [String: Any] = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .baggage(
                    key: LoggingMessageKeys.browserLog,
                    value: AnyEncodable(webLogEvent)
                ),
                from: core
            )
        )

        // Then
        let expectedWebLogEvent: [String: Any] = [
            "date": 1_635_932_927_012 + 123.toInt64Milliseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "version:\(applicationVersion),env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        let received: AnyEncodable = try XCTUnwrap(core.events().first, "It should send event")
        DDAssertJSONEqual(received, AnyEncodable(expectedWebLogEvent))
    }

    // MARK: - RUM Integration

    func testWhenRUMContextIsAvailable_itSendsLogWithRUMContext() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let applicationID: String = .mockRandom()
        let sessionID: String = .mockRandom()
        let viewID: String = .mockRandom()
        let actionID: String = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                baggages: [
                    "rum": .init([
                        "application.id": applicationID,
                        "session.id": sessionID,
                        "view.id": viewID,
                        "user_action.id": actionID
                    ])
                ]
            ),
            expectation: expectation(description: "Send log")
        )

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .baggage(
                    key: LoggingMessageKeys.browserLog,
                    value: AnyEncodable([ "test": "value" ])
                ),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(core.events.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertEqual(log["application_id"] as? String, applicationID)
        XCTAssertEqual(log["session_id"] as? String, sessionID)
        XCTAssertEqual(log["view.id"] as? String, viewID)
        XCTAssertEqual(log["user_action.id"] as? String, actionID)
    }

    func testWhenNoRUMContextIsAvailable_itDoesNotSendTelemetryError() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let telemetryReceiver = TelemetryReceiverMock()
        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send log"),
            messageReceiver: telemetryReceiver
        )

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .baggage(
                    key: LoggingMessageKeys.browserLog,
                    value: AnyEncodable([ "test": "value" ])
                ),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertNil(log["application_id"])
        XCTAssertNil(log["session_id"])
        XCTAssertNil(log["view.id"])
        XCTAssertNil(log["user_action.id"])
        XCTAssertTrue(telemetryReceiver.messages.isEmpty)
    }

    func testWhenRUMContextIsAvailable_withMalformedRUMContext_itSendsTelemetryError() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()
        let telemetryReceiver = TelemetryReceiverMock()
        let core = PassthroughCoreMock(
            context: .mockWith(
                baggages: [
                    "rum": .init("malformed RUM context")
                ]
            ),
            expectation: expectation(description: "Send log"),
            messageReceiver: telemetryReceiver
        )

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .baggage(
                    key: LoggingMessageKeys.browserLog,
                    value: AnyEncodable([ "test": "value" ])
                ),
                from: core
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let logs = core.events(ofType: AnyEncodable.self)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first?.value as? [String: Any])
        XCTAssertNil(log["application_id"])
        XCTAssertNil(log["session_id"])
        XCTAssertNil(log["view.id"])
        XCTAssertNil(log["user_action.id"])

        let error = try XCTUnwrap(telemetryReceiver.messages.first?.asError)
        XCTAssert(error.message.contains("Fails to decode RUM context from Logs in `WebViewLogReceiver` - typeMismatch"))
    }
}
