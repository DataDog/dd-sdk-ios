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

    func testWhenConfigurationIsDispatchedBeforeTheDelay_itIsDeliveredOnce() throws {
        // Given
        let core = PassthroughCoreMock()
        let receiver = FeatureMessageReceiverMock()
        let bus = MessageBus(configurationDispatchTime: .milliseconds(100))
        bus.connect(core: core)
        bus.connect(receiver, forKey: "receiver")
        bus.configuration(batchSize: 1)

        // When
        bus.dispatchPendingConfiguration()
        let configurationsBeforeTheDelay = receiver.messages.count
        wait(during: 0.3) { bus.flush() }

        // Then
        XCTAssertEqual(configurationsBeforeTheDelay, 1)
        XCTAssertEqual(receiver.messages.count, 1, "The delayed dispatch must not deliver the configuration again")
    }

    func testWhenDisconnected_itDoesNotDeliverMessages() throws {
        // Given
        let core = PassthroughCoreMock()
        let receiver = FeatureMessageReceiverMock()
        let bus = MessageBus()
        bus.connect(core: core)
        bus.connect(receiver, forKey: "receiver")
        bus.send(message: .payload("sent before disconnect"))
        bus.flush()

        let queueBlocked = DispatchSemaphore(value: 0)
        bus.queue.async { queueBlocked.wait() } // keep the next message queued until `disconnect()` returns
        let fallbacks = ReadWriteLock<[String]>(wrappedValue: [])
        bus.send(message: .payload("queued before disconnect"), else: { fallbacks.mutate { $0.append("queued before disconnect") } })

        // When
        bus.disconnect()
        queueBlocked.signal()
        bus.send(message: .payload("sent after disconnect"), else: { fallbacks.mutate { $0.append("sent after disconnect") } })
        bus.flush()

        // Then
        let deliveredPayloads = receiver.messages.compactMap { message -> String? in
            guard case .payload(let payload as String) = message else {
                return nil
            }
            return payload
        }
        XCTAssertEqual(deliveredPayloads, ["sent before disconnect"])
        XCTAssertEqual(fallbacks.wrappedValue, ["queued before disconnect", "sent after disconnect"], "Dropped messages must invoke their fallback")
    }

    #if os(macOS)
    func testWhenMessageIsQueued_suddenTerminationStaysDisabledUntilItIsDelivered() throws {
        // Given
        let suddenTermination = SuddenTerminationControlMock()
        let core = PassthroughCoreMock()
        let receiver = FeatureMessageReceiverMock()
        let bus = MessageBus(suddenTermination: suddenTermination)
        bus.connect(core: core)
        bus.connect(receiver, forKey: "receiver")
        let queueBlocked = DispatchSemaphore(value: 0)
        bus.queue.async { queueBlocked.wait() }

        // When
        bus.send(message: .payload("queued"))
        let isDisabledWhileQueued = suddenTermination.isDisabled
        queueBlocked.signal()
        bus.flush()

        // Then
        XCTAssertTrue(isDisabledWhileQueued)
        XCTAssertEqual(receiver.messages.count, 1)
        XCTAssertEqual(suddenTermination.disableCount, 0)
    }
    #endif
}

extension MessageBus: @retroactive Telemetry {
    public func send(telemetry: DatadogInternal.TelemetryMessage) {
        send(message: .telemetry(telemetry))
    }
}
