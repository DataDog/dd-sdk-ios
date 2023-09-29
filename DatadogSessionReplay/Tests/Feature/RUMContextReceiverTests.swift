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
        let core = PassthroughCoreMock(messageReceiver: receiver)

        var rumContext: RUMContext?
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        core.set(
            baggage: RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ),
            forKey: RUMContext.key
        )

        // Then
        XCTAssertEqual(rumContext?.applicationID, "app-id")
        XCTAssertEqual(rumContext?.sessionID, "session-id")
        XCTAssertEqual(rumContext?.viewID, "view-id")
        XCTAssertEqual(rumContext?.viewServerTimeOffset, 123)
    }

    func testWhenSucceedingMessagesContainDifferentRUMBaggages_itNotifiesRUMContextChange() throws {
        // Given
        let core = PassthroughCoreMock(messageReceiver: receiver)

        var rumContexts = [RUMContext]()
        receiver.observe(on: NoQueue()) { context in
            context.flatMap { rumContexts.append($0) }
        }
        // When
        core.set(
            baggage: RUMContextMock(
                applicationID: "app-id-1",
                sessionID: "session-id-1",
                viewID: "view-id-1",
                viewServerTimeOffset: 123
            ),
            forKey: RUMContext.key
        )

        core.set(
            baggage: RUMContextMock(
                applicationID: "app-id-2",
                sessionID: "session-id-2",
                viewID: "view-id-2",
                viewServerTimeOffset: 345
            ),
            forKey: RUMContext.key
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

    func testWhenMessageContainsNoRUMBaggage_itResetRUMContext() throws {
        // Given
        let core = PassthroughCoreMock(messageReceiver: receiver)

        var rumContext: RUMContext? = .mockAny()
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        core.set(
            baggage: RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ),
            forKey: RUMContext.key
        )

        XCTAssertEqual(rumContext?.applicationID, "app-id")
        XCTAssertEqual(rumContext?.sessionID, "session-id")
        XCTAssertEqual(rumContext?.viewID, "view-id")
        XCTAssertEqual(rumContext?.viewServerTimeOffset, 123)

        // When
        core.set(baggage: nil, forKey: RUMContext.key)
        // Then
        XCTAssertNil(rumContext)
    }

    func testWhenMessageContainsMalformedRUMBaggage_itSendsTelemetry() throws {
        // Given
        let telemetryReceiver = TelemetryMock()
        let core = PassthroughCoreMock(
            messageReceiver: CombinedFeatureMessageReceiver([
                receiver,
                telemetryReceiver
            ])
        )

        var rumContext: RUMContext? = .mockAny()
        receiver.observe(on: NoQueue()) { context in
            rumContext = context
        }

        // When
        core.set(
            baggage: RUMContextMock(
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: 123
            ),
            forKey: RUMContext.key
        )

        core.set(baggage: "malformed RUM context", forKey: "rum")

        // Then
        XCTAssertNil(rumContext)

        let error = try XCTUnwrap(telemetryReceiver.messages.first?.asError)
        XCTAssert(error.message.contains("Fails to decode RUM context from Session Replay - typeMismatch"))
    }
}
