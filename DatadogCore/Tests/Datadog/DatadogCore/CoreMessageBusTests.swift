/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCore

class CoreMessageBusTests: XCTestCase {
    func testCoreMessageBus() throws {
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

        let bus = CoreMessageBus()
        bus.connect(core: core)

        bus.connect(receiver, forKey: "receiver 1")
        bus.connect(receiver, forKey: "receiver 2")

        // When
        bus.send(message: .payload("value"))

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testItForwardConfigurationAfterDispatch() throws {
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
        let bus = CoreMessageBus(configurationDispatchTime: .milliseconds(90))
        bus.connect(core: core)
        bus.connect(receiver, forKey: "test")

        // When
        bus.configuration(batchSize: 1)
        bus.configuration(trackErrors: true)

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    // MARK: - typed bus (subscribe / unsubscribe / send)

    func testSubscribe_deliversMessageToReceiver() throws {
        let expectation = XCTestExpectation(description: "receiver invoked")

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        let receiver = AlphaReceiver { message, _ in
            XCTAssertEqual(message.value, "value")
            expectation.fulfill()
        }
        bus.subscribe(receiver: receiver)

        // When
        bus.send(message: AlphaMessage(value: "value"))

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testSubscribe_routesByMessageType() throws {
        let expectation = XCTestExpectation(description: "matching receiver invoked")
        expectation.assertForOverFulfill = true

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        let alpha = AlphaReceiver { _, _ in expectation.fulfill() }
        let beta = BetaReceiver { _, _ in
            XCTFail("BetaReceiver must not receive AlphaMessage")
        }
        bus.subscribe(receiver: alpha)
        bus.subscribe(receiver: beta)

        // When
        bus.send(message: AlphaMessage(value: "value"))

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testSubscribe_deliversToMultipleReceiversOfSameType() throws {
        let expectation = XCTestExpectation(description: "all receivers invoked")
        expectation.expectedFulfillmentCount = 3

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        let receivers = (0..<3).map { _ in
            AlphaReceiver { _, _ in expectation.fulfill() }
        }
        receivers.forEach { bus.subscribe(receiver: $0) }

        // When
        bus.send(message: AlphaMessage(value: "value"))

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testUnsubscribe_stopsDelivery() throws {
        let fallbackExpectation = XCTestExpectation(description: "fallback invoked")

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        let receiver = AlphaReceiver { _, _ in
            XCTFail("receiver must not be invoked after unsubscribe")
        }
        bus.subscribe(receiver: receiver)
        bus.unsubscribe(receiver: receiver)

        // When
        bus.send(message: AlphaMessage(value: "value")) { fallbackExpectation.fulfill() }

        // Then
        wait(for: [fallbackExpectation], timeout: 0.5)
        bus.flush()
    }

    func testSend_callsFallbackWhenNoSubscribers() throws {
        let expectation = XCTestExpectation(description: "fallback invoked")

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        // When
        bus.send(message: AlphaMessage(value: "value")) { expectation.fulfill() }

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testSend_callsFallbackWhenCoreNotConnected() throws {
        let expectation = XCTestExpectation(description: "fallback invoked")

        // Given (no `connect(core:)` call)
        let bus = CoreMessageBus()
        let receiver = AlphaReceiver { _, _ in
            XCTFail("receiver must not be invoked without a connected core")
        }
        bus.subscribe(receiver: receiver)

        // When
        bus.send(message: AlphaMessage(value: "value")) { expectation.fulfill() }

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testSend_doesNotCallFallbackWhenDelivered() throws {
        let delivery = XCTestExpectation(description: "receiver invoked")
        let fallback = XCTestExpectation(description: "fallback NOT invoked")
        fallback.isInverted = true

        // Given
        let core = PassthroughCoreMock()
        let bus = CoreMessageBus()
        bus.connect(core: core)

        let receiver = AlphaReceiver { _, _ in delivery.fulfill() }
        bus.subscribe(receiver: receiver)

        // When
        bus.send(message: AlphaMessage(value: "value")) { fallback.fulfill() }

        // Then
        wait(for: [delivery, fallback], timeout: 0.5)
        bus.flush()
    }
}

// MARK: - typed-bus fixtures

private struct AlphaMessage: BusMessage {
    static let key = "test.alpha"
    let value: String
}

private struct BetaMessage: BusMessage {
    static let key = "test.beta"
}

private final class AlphaReceiver: BusMessageReceiver {
    typealias Message = AlphaMessage

    let onReceive: (AlphaMessage, DatadogCoreProtocol) -> Void

    init(_ onReceive: @escaping (AlphaMessage, DatadogCoreProtocol) -> Void) {
        self.onReceive = onReceive
    }

    func receive(message: AlphaMessage, from core: DatadogCoreProtocol) {
        onReceive(message, core)
    }
}

private final class BetaReceiver: BusMessageReceiver {
    typealias Message = BetaMessage

    let onReceive: (BetaMessage, DatadogCoreProtocol) -> Void

    init(_ onReceive: @escaping (BetaMessage, DatadogCoreProtocol) -> Void) {
        self.onReceive = onReceive
    }

    func receive(message: BetaMessage, from core: DatadogCoreProtocol) {
        onReceive(message, core)
    }
}

extension CoreMessageBus: @retroactive Telemetry {
    public func send(telemetry: DatadogInternal.TelemetryMessage) {
        send(message: .telemetry(telemetry))
    }
}
