/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM

@testable import DatadogCore

class MessageBusTests: XCTestCase {
    func testFlagEnvelopeCrossesActualAsyncBusWithoutChangingOrigin() throws {
        let core = PassthroughCoreMock()
        let scope = FeatureScopeMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: scope, samplingRate: 100), dateProvider: SystemDateProvider())
        let a = RUMSceneIdentifier(rawValue: "A")
        let b = RUMSceneIdentifier(rawValue: "B")
        monitor.process(command: RUMStartViewCommand.mockWith(identity: ViewIdentifier("A"), name: "A", target: .scene(a)))
        monitor.process(command: RUMStartViewCommand.mockWith(identity: ViewIdentifier("B"), name: "B", target: .scene(b)))
        let origin = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(a)))
        let receiver = FlagEvaluationReceiver(monitor: monitor)
        let delivered = expectation(description: "captured flag delivered")
        let bus = MessageBus()
        defer {
            bus.removeReceiver(forKey: "rum")
            bus.flush()
        }
        bus.connect(core: core)
        bus.connect(FeatureMessageReceiverMock { message in
            XCTAssertNil(RUMContextHandoff.current(for: scope.rumContextHandoffOwner))
            XCTAssertTrue(receiver.receive(message: message, from: core))
            delivered.fulfill()
        }, forKey: "rum")
        let release = DispatchSemaphore(value: 0)
        bus.queue.async { XCTAssertEqual(release.wait(timeout: .now() + 2), .success) }
        try RUMContextHandoff.withValue(owner: scope.rumContextHandoffOwner, rumContext: origin, sceneIdentifier: a.rawValue) {
            let captured = try XCTUnwrap(RUMFlagEvaluationContextMessage(
                evaluation: RUMFlagEvaluationMessage(flagKey: "delayed", value: 7), in: scope
            ))
            bus.send(message: .payload(captured))
        }
        release.signal()
        wait(for: [delivered], timeout: 3)
        bus.flush()
        let views = try XCTUnwrap(monitor.applicationScope.activeSession).viewScopes
        XCTAssertEqual(views.first { $0.sceneIdentifier == a }?.featureFlags["delayed"] as? Int, 7)
        XCTAssertNil(views.first { $0.sceneIdentifier == b }?.featureFlags["delayed"])
    }

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
        bus.configuration(trackErrors: true)

        // Then
        wait(for: [expectation], timeout: 0.5)
        bus.flush()
    }
}

extension MessageBus: @retroactive Telemetry {
    public func send(telemetry: DatadogInternal.TelemetryMessage) {
        send(message: .telemetry(telemetry))
    }
}
