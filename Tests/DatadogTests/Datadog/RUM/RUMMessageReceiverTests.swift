/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class RUMMessageReceiverTests: XCTestCase {
    func testReceiveIncompleteError() throws {
        let expectation = expectation(description: "Don't send error fallback")

        // Given
        let core = PassthroughCoreMock(
            messageReceiver: RUMMessageReceiver()
        )

        Global.rum = RUMMonitor.init(core: core, dependencies: .mockAny(), dateProvider: SystemDateProvider())
        defer { Global.rum = DDNoopRUMMonitor() }

        // When
        core.send(
            message: .error(
                message: "message-test",
                baggage: [:]
            ),
            else: { expectation.fulfill() }
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testReceivePartialError() throws {
        // Given
        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Error"),
            messageReceiver: RUMMessageReceiver()
        )

        Global.rum = RUMMonitor.init(core: core, dependencies: .mockAny(), dateProvider: SystemDateProvider())
        defer { Global.rum = DDNoopRUMMonitor() }

        // When
        core.send(
            message: .error(
                message: "message-test",
                baggage: [
                    "source": "custom"
                ]
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let event: RUMErrorEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.source, .custom)
    }

    func testReceiveCompleteError() throws {
        // Given
        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Error"),
            messageReceiver: RUMMessageReceiver()
        )

        Global.rum = RUMMonitor.init(core: core, dependencies: .mockAny(), dateProvider: SystemDateProvider())
        defer { Global.rum = DDNoopRUMMonitor() }

        // When
        core.send(
            message: .error(
                message: "message-test",
                baggage: [
                    "type": "type-test",
                    "stack": "stack-test",
                    "source": "logger"
                ]
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let event: RUMErrorEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.type, "type-test")
        XCTAssertEqual(event.error.stack, "stack-test")
        XCTAssertEqual(event.error.source, .logger)
    }

    func testReceiveEvent() throws {
        // Given
        struct Event: Encodable {
            let test: String
        }

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send Event"),
            messageReceiver: RUMMessageReceiver()
        )

        // When
        let sent: [String: Any] = [
            "test": String.mockRandom()
        ]

        core.send(
            message: .custom(key: RUMMessageKeys.browserEvent, baggage: .init(sent))
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let received: AnyEncodable = try XCTUnwrap(core.events().last, "It should send event")
        try AssertEncodedRepresentationsEqual(received, AnyEncodable(sent))
    }

    func testReceiveCrashEvent() throws {
        // Given
        let core = PassthroughCoreMock(
            bypassConsentExpectation: expectation(description: "Send Event Bypass Consent"),
            messageReceiver: RUMMessageReceiver()
        )

        // When
        let sentError: RUMCrashEvent = .mockRandom()

        core.send(
            message: .custom(key: RUMMessageKeys.crash, baggage: [
                "rum-error": sentError
            ])
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let receivedError: RUMCrashEvent = try XCTUnwrap(core.events().last, "It should send event")
        try AssertEncodedRepresentationsEqual(sentError, receivedError)
    }

    func testReceiveCrashAndViewEvent() throws {
        // Given
        let core = PassthroughCoreMock(
            bypassConsentExpectation: expectation(description: "Send Event Bypass Consent"),
            messageReceiver: RUMMessageReceiver()
        )

        // When
        let sentError: RUMCrashEvent = .mockRandom()
        let sentView: RUMViewEvent = .mockRandom()

        core.send(
            message: .custom(key: RUMMessageKeys.crash, baggage: [
                "rum-error": sentError,
                "rum-view": sentView
            ])
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let receivedError: RUMCrashEvent = try XCTUnwrap(core.events().last, "It should send event")
        let receivedView: RUMViewEvent = try XCTUnwrap(core.events().last, "It should send event")
        try AssertEncodedRepresentationsEqual(sentError, receivedError)
        try AssertEncodedRepresentationsEqual(sentView, receivedView)
    }
}
