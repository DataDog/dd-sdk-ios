/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class ErrorMessageReceiverTests: XCTestCase {
    let messageReceiver = ErrorMessageReceiver()

    func testReceiveIncompleteError() throws {
        let expectation = expectation(description: "Don't send error fallback")

        // Given
        let core = PassthroughCoreMock(
            messageReceiver: messageReceiver
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
            messageReceiver: messageReceiver
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
            messageReceiver: messageReceiver
        )

        Global.rum = RUMMonitor.init(core: core, dependencies: .mockAny(), dateProvider: SystemDateProvider())
        defer { Global.rum = DDNoopRUMMonitor() }

        // When
        let mockAttribute: String = .mockRandom()
        core.send(
            message: .error(
                message: "message-test",
                baggage: [
                    "type": "type-test",
                    "stack": "stack-test",
                    "source": "logger",
                    "attributes": [
                        "any-key": mockAttribute
                    ]
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
        let attributeValue = (event.context?.contextInfo["any-key"] as? DDAnyCodable)?.value as? String
        XCTAssertEqual(attributeValue, mockAttribute)
    }
}
