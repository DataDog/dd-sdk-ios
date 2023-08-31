/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogRUM
@testable import DatadogCore

class WebViewLogReceiverTests: XCTestCase {
    func testReceiveEvent() throws {
        // Given
        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Event"),
            messageReceiver: WebViewLogReceiver()
        )

        // When
        let value: String = .mockRandom()

        core.send(
            message: .baggage(key: LoggingMessageKeys.browserLog, value: AnyEncodable([
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

        DDAssertJSONEqual(received, AnyEncodable(expected))
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
                        "ids": [
                            RUMContextAttributes.IDs.applicationID: "123456",
                            RUMContextAttributes.IDs.sessionID: mockSessionID.uuidString.lowercased()
                        ]
                    ]
                ]
            ),
            messageReceiver: WebViewLogReceiver()
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
            message: .baggage(
                key: LoggingMessageKeys.browserLog,
                value: AnyCodable(webLogEvent)
            )
        )

        let received: AnyEncodable = try XCTUnwrap(core.events().first, "It should send event")
        DDAssertJSONEqual(received, AnyEncodable(expectedWebLogEvent))
    }

    func testWhenContextIsUnavailable_itPassesWebviewEventAsIs() throws {
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(
                env: environment,
                version: applicationVersion
            ),
            messageReceiver: WebViewLogReceiver()
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
            message: .baggage(
                key: LoggingMessageKeys.browserLog,
                value: AnyEncodable(webLogEvent)
            )
        )

        let received: AnyEncodable = try XCTUnwrap(core.events().first, "It should send event")
        DDAssertJSONEqual(received, AnyEncodable(expectedWebLogEvent))
    }
}
