/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCore

class MessageBusTests: XCTestCase {
    func testMessageBus() async throws {
        let expectation = XCTestExpectation(description: "dispatch message")
        expectation.expectedFulfillmentCount = 2

        // Given
        let core = PassthroughCoreMock()

        let receiver = FeatureMessageReceiverMock { message in
            // Then
            switch message {
            case let .payload(payload as String) where payload == "value":
                expectation.fulfill()
            default:
                XCTFail("wrong message case")
            }
        }

        let bus = MessageBus()
        await bus.connect(core: core)

        await bus.connect(receiver, forKey: "receiver 1")
        await bus.connect(receiver, forKey: "receiver 2")

        // When
        await bus.send(message: .payload("value"))

        // Then
        await fulfillment(of: [expectation], timeout: 0.5)
    }

    func testItForwardConfigurationAfterDispatch() async throws {
        let expectation = XCTestExpectation(description: "dispatch configuration")
        let receiver = FeatureMessageReceiverMock { message in
            guard
                case .telemetry(let telemetry) = message,
                case .configuration(let configuration) = telemetry
            else {
                return XCTFail("Message bus should send configuration telemetry")
            }

            XCTAssertEqual(configuration.batchSize, 1)
            XCTAssertTrue(configuration.trackErrors ?? false)
            expectation.fulfill()
        }

        // Given
        let core = PassthroughCoreMock()
        let bus = MessageBus(configurationDispatchDelay: 90_000_000)
        await bus.connect(core: core)
        await bus.connect(receiver, forKey: "test")

        // When
        await bus.send(message: .telemetry(.configuration(.init(batchSize: 1))))
        await bus.send(message: .telemetry(.configuration(.init(trackErrors: true))))

        // Then
        await fulfillment(of: [expectation], timeout: 0.5)
    }
}
