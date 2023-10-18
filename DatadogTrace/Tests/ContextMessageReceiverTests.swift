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
        let core = PassthroughCoreMock()

        let coreContext1: DatadogContext = .mockWith(
            baggages: [
                "rum": .init([
                    "application.id": "app-id",
                    "session.id": "session-id",
                    "view.id": "view-id",
                    "user_action.id": "action-id"
                ])
            ]
        )

        let coreContext2: DatadogContext = .mockWith(
            baggages: [
                "rum": .init([
                    "application.id": "app-id",
                    "session.id": "session-id",
                    "view.id": nil,
                    "user_action.id": nil
                ])
            ]
        )

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext1), from: core)
        )

        // Then
        XCTAssertEqual(receiver.context.rum?["_dd.application.id"], "app-id")
        XCTAssertEqual(receiver.context.rum?["_dd.session.id"], "session-id")
        XCTAssertEqual(receiver.context.rum?["_dd.view.id"], "view-id")
        XCTAssertEqual(receiver.context.rum?["_dd.action.id"], "action-id")

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext2), from: core)
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
        let core = PassthroughCoreMock()

        let coreContext: DatadogContext = .mockWith(
            baggages: [
                "rum": .init([
                    "application.id": "app-id",
                    "session.id": "session-id",
                    "view.id": "view-id",
                    "user_action.id": "action-id"
                ])
            ]
        )

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext), from: core)
        )

        // Then
        XCTAssertEqual(receiver.context.rum?["_dd.application.id"], "app-id")
        XCTAssertEqual(receiver.context.rum?["_dd.session.id"], "session-id")
        XCTAssertEqual(receiver.context.rum?["_dd.view.id"], "view-id")
        XCTAssertEqual(receiver.context.rum?["_dd.action.id"], "action-id")

        // When
        XCTAssert(
            receiver.receive(message: .context(.mockAny()), from: core)
        )

        // Then
        XCTAssertNil(receiver.context.rum)
    }

    func testItReceivesMalformedRUMContext() throws {
        // Given
        let telemetryReceiver = TelemetryReceiverMock()
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: true)
        let core = PassthroughCoreMock(
            messageReceiver: telemetryReceiver
        )

        let coreContext: DatadogContext = .mockWith(
            baggages: [
                "rum": .init("malformed RUM context")
            ]
        )

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext), from: core)
        )

        // Then
        XCTAssertNil(receiver.context.rum)

        let error = try XCTUnwrap(telemetryReceiver.messages.first?.asError)
        XCTAssert(error.message.contains("Fails to decode RUM context from Trace - typeMismatch"))
    }

    func testItIngnoresRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: false)
        let core = PassthroughCoreMock()
        let coreContext: DatadogContext = .mockWith(
            baggages: [
                "rum": .init([
                    "application.id": "app-id",
                    "session.id": "session-id",
                    "view.id": "view-id",
                    "user_action.id": "action-id"
                ])
            ]
        )

        // When
        XCTAssert(
            receiver.receive(message: .context(coreContext), from: core)
        )

        XCTAssertNil(receiver.context.rum)
    }
}
