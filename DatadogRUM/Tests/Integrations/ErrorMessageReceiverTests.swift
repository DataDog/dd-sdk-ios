/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

class ErrorMessageReceiverTests: XCTestCase {
    var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()

        core = PassthroughCoreMock()
        core.messageReceiver = ErrorMessageReceiver(
            monitor: Monitor(
                core: core,
                dependencies: .mockAny(),
                dateProvider: SystemDateProvider()
            )
        )
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testReceiveIncompleteError() throws {
        let expectation = expectation(description: "Don't send error fallback")

        // When
        try core.send(
            message: .baggage(key: "error", value: ["message": "message-test"]),
            else: { expectation.fulfill() }
        )

        let errorEvents = core.events(ofType: RUMErrorEvent.self)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(errorEvents.isEmpty)
    }

    func testReceivePartialError() throws {
        core.expectation = expectation(description: "Send Error")

        // When
        try core.send(
            message: .baggage(key: "error", value: [
                "message": "message-test",
                "source": "custom"
            ])
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let event: RUMErrorEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.source, .custom)
    }

    func testReceiveCompleteError() throws {
        core.expectation = expectation(description: "Send Error")

        // When
        let mockAttribute: String = .mockRandom()
        let baggage: [String: Any] = [
            "message": "message-test",
            "type": "type-test",
            "stack": "stack-test",
            "source": "logger",
            "attributes": [
                "any-key": mockAttribute
            ]
        ]
        try core.send(
            message: .baggage(key: "error", value: AnyEncodable(baggage))
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let event: RUMErrorEvent = try XCTUnwrap(core.events().last, "It should send log")
        XCTAssertEqual(event.error.message, "message-test")
        XCTAssertEqual(event.error.type, "type-test")
        XCTAssertEqual(event.error.stack, "stack-test")
        XCTAssertEqual(event.error.source, .logger)
        let attributeValue = (event.context?.contextInfo["any-key"] as? AnyCodable)?.value as? String
        XCTAssertEqual(attributeValue, mockAttribute)
    }
}
