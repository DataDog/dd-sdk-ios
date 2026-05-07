/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class MessageBusTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var bus: MessageBusSpy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
        bus = MessageBusSpy(core: core)
    }

    override func tearDown() {
        core = nil
        bus = nil
        super.tearDown()
    }

    // MARK: - subscribe(block:)

    func testSubscribeBlock_registersOneReceiverWithBus() {
        _ = bus.subscribe { (_: AlphaMessage, _) in }

        XCTAssertEqual(bus.subscribedReceivers.count, 1)
    }

    func testSubscribeBlock_deliversMatchingMessageToClosure() {
        let received = expectation(description: "closure invoked")
        var payload: AlphaMessage?

        _ = bus.subscribe { (message: AlphaMessage, _) in
            payload = message
            received.fulfill()
        }

        bus.send(message: AlphaMessage(value: 42))

        wait(for: [received], timeout: 1)
        XCTAssertEqual(payload?.value, 42)
    }

    func testSubscribeBlock_forwardsEmittingCoreToClosure() {
        let received = expectation(description: "closure invoked")
        var forwardedCore: DatadogCoreProtocol?

        _ = bus.subscribe { (_: AlphaMessage, core: DatadogCoreProtocol) in
            forwardedCore = core
            received.fulfill()
        }

        bus.send(message: AlphaMessage(value: 0))

        wait(for: [received], timeout: 1)
        XCTAssertTrue(forwardedCore === core)
    }

    func testSubscribeBlock_routesByMessageType() {
        var alphaCount = 0
        var betaCount = 0

        _ = bus.subscribe { (_: AlphaMessage, _) in alphaCount += 1 }
        _ = bus.subscribe { (_: BetaMessage, _) in betaCount += 1 }

        bus.send(message: AlphaMessage(value: 0))
        XCTAssertEqual(alphaCount, 1)
        XCTAssertEqual(betaCount, 0)

        bus.send(message: BetaMessage(label: "x"))
        XCTAssertEqual(alphaCount, 1)
        XCTAssertEqual(betaCount, 1)
    }

    // MARK: - unsubscribe(_:)

    func testUnsubscribeSubscription_removesTheSameReceiverThatWasSubscribed() {
        let subscription = bus.subscribe { (_: AlphaMessage, _) in }
        let registered = bus.subscribedReceivers.first

        bus.unsubscribe(subscription)

        XCTAssertEqual(bus.unsubscribedReceivers.count, 1)
        XCTAssertTrue(bus.unsubscribedReceivers.first === registered)
    }
}

// MARK: - Test fixtures

private struct AlphaMessage: BusMessage {
    static let key = "test.alpha"
    let value: Int
}

private struct BetaMessage: BusMessage {
    static let key = "test.beta"
    let label: String
}

/// A test double that records subscribe/unsubscribe calls and dispatches
/// `send` to every captured receiver — the per-receiver closure filters by
/// type, so cross-type sends are ignored without ceremony.
private final class MessageBusSpy: MessageBus {
    let core: DatadogCoreProtocol
    private(set) var subscribedReceivers: [AnyObject] = []
    private(set) var unsubscribedReceivers: [AnyObject] = []
    private var deliveryActions: [(Any, DatadogCoreProtocol) -> Void] = []

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        subscribedReceivers.append(receiver)
        deliveryActions.append { message, core in
            guard let typed = message as? Receiver.Message else {
                return
            }
            receiver.receive(message: typed, from: core)
        }
    }

    func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        unsubscribedReceivers.append(receiver)
    }

    func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage {
        deliveryActions.forEach { $0(message, core) }
    }
}
