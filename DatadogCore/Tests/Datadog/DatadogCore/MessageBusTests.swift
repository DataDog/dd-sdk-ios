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
    func testMessageBus() throws {
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
            XCTAssertEqual(configuration.profilingApplicationLaunchSampleRate, 12.5)
            XCTAssertEqual(configuration.profilingSampleRate, 37.5)
            XCTAssertTrue(configuration.trackErrors ?? false)
            expectation.fulfill()
        }

        // Given
        let core = PassthroughCoreMock()
        let bus = MessageBus(configurationDispatchTime: .milliseconds(90))
        bus.connect(core: core)
        bus.connect(receiver, forKey: "test")

        // When
        bus.configuration(batchSize: 1)
        bus.configuration(profilingApplicationLaunchSampleRate: 12.5, profilingSampleRate: 37.5)
        bus.configuration(trackErrors: true)

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }

    func testWhenDisconnected_itDoesNotDeliverMessages() throws {
        // Given
        let core = PassthroughCoreMock()
        let receiver = FeatureMessageReceiverMock()
        let bus = MessageBus()
        bus.connect(core: core)
        bus.connect(receiver, forKey: "receiver")
        bus.send(message: .payload("sent before disconnect"))

        // When
        bus.disconnect()
        bus.send(message: .payload("sent after disconnect"))
        bus.flush()

        // Then
        let deliveredPayloads = receiver.messages.compactMap { message -> String? in
            guard case .payload(let payload as String) = message else {
                return nil
            }
            return payload
        }
        XCTAssertEqual(deliveredPayloads, ["sent before disconnect"])
    }

    func testWhenDisconnected_itDoesNotDispatchConfiguration() throws {
        // Given
        let core = PassthroughCoreMock()
        let receiver = FeatureMessageReceiverMock()
        let bus = MessageBus(configurationDispatchTime: .milliseconds(50))
        bus.connect(core: core)
        bus.connect(receiver, forKey: "receiver")
        bus.configuration(batchSize: 1)

        // When
        bus.disconnect()

        // Then
        let dispatchTimePassed = expectation(description: "configuration dispatch time passed")
        bus.queue.asyncAfter(deadline: .now() + .milliseconds(100)) { dispatchTimePassed.fulfill() }
        wait(for: [dispatchTimePassed], timeout: 1)
        XCTAssertTrue(receiver.messages.isEmpty, "Configuration telemetry must not be dispatched after disconnection")
    }
}

extension MessageBus: @retroactive Telemetry {
    public func send(telemetry: DatadogInternal.TelemetryMessage) {
        send(message: .telemetry(telemetry))
    }
}
