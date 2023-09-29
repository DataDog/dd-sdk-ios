/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogSessionReplay

class RUMContextReceiverTests: XCTestCase {
    private let receiver = RUMContextReceiver()

    internal struct RUMContextMock: Encodable {
        enum CodingKeys: String, CodingKey {
            case applicationID = "application.id"
            case sessionID = "session.id"
            case viewID = "view.id"
            case viewServerTimeOffset = "server_time_offset"
        }

        let applicationID: String
        let sessionID: String
        let viewID: String?
        let viewServerTimeOffset: TimeInterval?
    }

    func testWhenMessageContainsNonEmptyRUMBaggage_itNotifiesRUMContext() throws {
        // Given
        let core = PassthroughCoreMock()
        let coreContext: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ))
        ])

        var rumContext: RUMContext?
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext), from: core)
        )

        // Then
        XCTAssertEqual(rumContext?.applicationID, "app-id")
        XCTAssertEqual(rumContext?.sessionID, "session-id")
        XCTAssertEqual(rumContext?.viewID, "view-id")
        XCTAssertEqual(rumContext?.viewServerTimeOffset, 123)
    }

    func testWhenSucceedingMessagesContainDifferentRUMBaggages_itNotifiesRUMContextChange() throws {
        // Given
        let core = PassthroughCoreMock()
        let coreContext1: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id-1",
                sessionID: "session-id-1",
                viewID: "view-id-1",
                viewServerTimeOffset: 123
            ))
        ])

        let coreContext2: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id-2",
                sessionID: "session-id-2",
                viewID: "view-id-2",
                viewServerTimeOffset: 345
            ))
        ])

        var rumContexts: [RUMContext] = []
        receiver.observe(on: NoQueue()) { context in
            context.flatMap { rumContexts.append($0) }
        }
        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext1), from: core)
        )

        XCTAssert(
            receiver.receive(message: .context(coreContext2), from: core)
        )

        // Then
        XCTAssertEqual(rumContexts.count, 2)
        XCTAssertEqual(rumContexts[0].applicationID, "app-id-1")
        XCTAssertEqual(rumContexts[0].sessionID, "session-id-1")
        XCTAssertEqual(rumContexts[0].viewID, "view-id-1")
        XCTAssertEqual(rumContexts[0].viewServerTimeOffset, 123)
        XCTAssertEqual(rumContexts[1].applicationID, "app-id-2")
        XCTAssertEqual(rumContexts[1].sessionID, "session-id-2")
        XCTAssertEqual(rumContexts[1].viewID, "view-id-2")
        XCTAssertEqual(rumContexts[1].viewServerTimeOffset, 345)
    }

    func testWhenSucceedingMessagesContainSameRUMBaggages_itNotifiesRUMContextChangeOnce() throws {
        // Given
        let core = PassthroughCoreMock()
        let coreContext1: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ))
        ])

        let coreContext2: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ))
        ])

        var rumContexts: [RUMContext] = []
        receiver.observe(on: NoQueue()) { context in
            context.flatMap { rumContexts.append($0) }
        }
        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext1), from: core)
        )

        XCTAssert(
            receiver.receive(message: .context(coreContext2), from: core)
        )

        // Then
        XCTAssertEqual(rumContexts.count, 1)
        XCTAssertEqual(rumContexts[0].applicationID, "app-id")
        XCTAssertEqual(rumContexts[0].sessionID, "session-id")
        XCTAssertEqual(rumContexts[0].viewID, "view-id")
        XCTAssertEqual(rumContexts[0].viewServerTimeOffset, 123)
    }

    func testWhenMessageContainsNoRUMBaggage_itResetRUMContext() throws {
        // Given
        let core = PassthroughCoreMock()
        let coreContext1: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ))
        ])

        let coreContext2: DatadogContext = .mockWith()

        var rumContext: RUMContext? = .mockAny()
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext1), from: core)
        )

        XCTAssertEqual(rumContext?.applicationID, "app-id")
        XCTAssertEqual(rumContext?.sessionID, "session-id")
        XCTAssertEqual(rumContext?.viewID, "view-id")
        XCTAssertEqual(rumContext?.viewServerTimeOffset, 123)

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext2), from: core)
        )
        // Then
        XCTAssertNil(rumContext)
    }

    func testWhenMessageContainsMalformedRUMBaggage_itSendsTelemetry() throws {
        // Given
        let telemetryReceiver = TelemetryReceiverMock()
        let core = PassthroughCoreMock(
            messageReceiver: telemetryReceiver
        )

        let coreContext1: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init(RUMContextMock(
                applicationID: "app-id-1",
                sessionID: "session-id-1",
                viewID: "view-id-1",
                viewServerTimeOffset: 123
            ))
        ])

        let coreContext2: DatadogContext = .mockWith(baggages: [
            RUMContext.key: .init("malformed RUM context")
        ])

        var rumContext: RUMContext? = .mockAny()
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext1), from: core)
        )

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext2), from: core)
        )

        // Then
        XCTAssertNil(rumContext)

        let error = try XCTUnwrap(telemetryReceiver.messages.first?.asError)
        XCTAssert(error.message.contains("Fails to decode RUM context from Session Replay - typeMismatch"))
    }

    func testWhenMessageIsNotContext_itReturnsFalse() throws {
        // Given
        let expectation = expectation(description: "observe not called")
        expectation.isInverted = true
        let core = PassthroughCoreMock()

        receiver.observe(on: NoQueue()) { _ in
            expectation.fulfill()
        }

        // When
        XCTAssertFalse(
            receiver.receive(message: .baggage(key: "key", value: "value"), from: core)
        )

        // Then
        waitForExpectations(timeout: 0.1)
    }
}
