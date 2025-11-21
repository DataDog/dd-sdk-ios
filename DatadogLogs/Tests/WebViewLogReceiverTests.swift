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
    func testParsingLogEvent() throws {
        // Given
        let data = """
        {
          "eventType": "log",
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            },
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": {
              "referrer": "",
              "url": "https://datadoghq.dev/browser-sdk-test-playground"
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """.utf8Data

        // When
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebViewMessage.self, from: data)

        guard case let .log(event) = message else {
            return XCTFail("not a log message")
        }

        // Then
        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("date"), 1_635_932_927_012)
        XCTAssertEqual(try json.value("error.origin"), "console")
        XCTAssertEqual(try json.value("message"), "console error: error")
        XCTAssertEqual(try json.value("session_id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual(try json.value("status"), "error")
        XCTAssertEqual(try json.value("view.referrer"), "")
        XCTAssertEqual(try json.value("view.url"), "https://datadoghq.dev/browser-sdk-test-playground")
    }

    func testReceiveEvent() throws {
        // Given
        let messageReceiver = WebViewLogReceiver()

        let expectation = expectation(description: "Send Event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in expectation.fulfill() }

        let value: String = .mockRandom()

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": value])),
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
                additionalContext: [
                    RUMCoreContext(
                        applicationID: "123456",
                        sessionID: mockSessionID.uuidString.lowercased()
                    )
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
                message: .webview(.log(webLogEvent)),
                from: core
            )
        )

        // Then
        let expectedWebLogEvent: [String: Any] = [
            "date": 1_635_932_927_012 + 123.dd.toInt64Milliseconds,
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

        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(
            context: .mockWith(
                additionalContext: [
                    RUMCoreContext(
                        applicationID: applicationID,
                        sessionID: sessionID,
                        viewID: viewID,
                        userActionID: actionID
                    )
                ]
            )
        )
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
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
        let expectation = expectation(description: "Send log")
        let core = PassthroughCoreMock(messageReceiver: telemetryReceiver)
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // When
        XCTAssert(
            messageReceiver.receive(
                message: .webview(.log(["test": "value"])),
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
}
