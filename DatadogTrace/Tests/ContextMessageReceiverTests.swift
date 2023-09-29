/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class ContextMessageReceiverTests: XCTestCase {
    func testItReceivesApplicationStateHistory() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: .mockRandom())
        let core = PassthroughCoreMock(
            context: .mockWith(applicationStateHistory: .mockAppInBackground()),
            messageReceiver: receiver
        )

        XCTAssertEqual(receiver.context.applicationStateHistory?.initialSnapshot.state, .background)

        // When
        core.context.applicationStateHistory.append(.init(state: .active, date: Date()))

        // Then
        XCTAssertEqual(receiver.context.applicationStateHistory?.currentSnapshot.state, .active)
    }

    func testItReceivesRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: true)
        let core = PassthroughCoreMock(
            context: .mockWith(
                baggages: [
                    "rum": .init([
                        "application.id": "app-id",
                        "session.id": "session-id",
                        "view.id": "view-id",
                        "user_action.id": "action-id"
                    ])
                ]
            ),
            messageReceiver: receiver
        )

        XCTAssertEqual(receiver.context.rum?["_dd.application.id"], "app-id")
        XCTAssertEqual(receiver.context.rum?["_dd.session.id"], "session-id")
        XCTAssertEqual(receiver.context.rum?["_dd.view.id"], "view-id")
        XCTAssertEqual(receiver.context.rum?["_dd.action.id"], "action-id")

        // When
        core.set(
            baggage: [
                "application.id": "app-id",
                "session.id": "session-id",
                "view.id": nil,
                "user_action.id": nil
            ],
            forKey: "rum"
        )

        // Then
        XCTAssertEqual(receiver.context.rum?["_dd.application.id"], "app-id")
        XCTAssertEqual(receiver.context.rum?["_dd.session.id"], "session-id")
        XCTAssertNil(receiver.context.rum?["_dd.view.id"])
        XCTAssertNil(receiver.context.rum?["_dd.action.id"])
    }

    func testItReceivesNilRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: true)
        let core = PassthroughCoreMock(
            context: .mockWith(
                baggages: [
                    "rum": .init([
                        "application.id": "app-id",
                        "session.id": "session-id",
                        "view.id": "view-id",
                        "user_action.id": "action-id"
                    ])
                ]
            ),
            messageReceiver: receiver
        )

        XCTAssertEqual(receiver.context.rum?["_dd.application.id"], "app-id")
        XCTAssertEqual(receiver.context.rum?["_dd.session.id"], "session-id")
        XCTAssertEqual(receiver.context.rum?["_dd.view.id"], "view-id")
        XCTAssertEqual(receiver.context.rum?["_dd.action.id"], "action-id")

        // When
        core.set(baggage: nil, forKey: "rum")

        // Then
        XCTAssertNil(receiver.context.rum)
    }

    func testItReceivesMalformedRUMContext() throws {
        // Given
        let telemetryReceiver = TelemetryMock()
        let contextReceiver = ContextMessageReceiver(bundleWithRumEnabled: true)
        let core = PassthroughCoreMock(
            messageReceiver: CombinedFeatureMessageReceiver([
                contextReceiver,
                telemetryReceiver
            ])
        )

        // When
        core.set(baggage: "malformed RUM context", forKey: "rum")

        // Then
        XCTAssertNil(contextReceiver.context.rum)

        let error = try XCTUnwrap(telemetryReceiver.messages.first?.asError)
        XCTAssert(error.message.contains("Fails to decode RUM context from Trace - typeMismatch"))
    }

    func testItIngnoresRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: false)
        var ids: [String: String?] = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(baggages: ["rum": .init(ids)]),
            messageReceiver: receiver
        )

        XCTAssertNil(receiver.context.rum)

        // When
        ids = .mockRandom()
        core.set(baggage: ids, forKey: "rum")

        // Then
        XCTAssertNil(receiver.context.rum)
    }
}
