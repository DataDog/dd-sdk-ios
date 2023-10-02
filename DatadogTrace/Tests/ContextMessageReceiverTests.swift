/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

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
        var ids: [String: String?] = [
            "application.id": "app-id",
            "session.id": "session-id",
            "view.id": "view-id",
            "user_action.id": "action-id"
        ]

        let core = PassthroughCoreMock(
            context: .mockWith(featuresAttributes: ["rum": ["ids": ids]]),
            messageReceiver: receiver
        )

        var rumContext = try XCTUnwrap(receiver.context.rum)
        XCTAssertEqual(rumContext["_dd.application.id"] as? String, "app-id")
        XCTAssertEqual(rumContext["_dd.session.id"] as? String, "session-id")
        XCTAssertEqual(rumContext["_dd.view.id"] as? String, "view-id")
        XCTAssertEqual(rumContext["_dd.action.id"] as? String, "action-id")

        // When
        ids = [
            "application.id": "app-id",
            "session.id": "session-id",
            "view.id": nil,
            "user_action.id": nil
        ]
        core.set(feature: "rum", attributes: { ["ids": ids] })

        // Then
        rumContext = try XCTUnwrap(receiver.context.rum)
        XCTAssertEqual(rumContext["_dd.application.id"] as? String, "app-id")
        XCTAssertEqual(rumContext["_dd.session.id"] as? String, "session-id")
        XCTAssertNil(rumContext["_dd.view.id"] as Any?)
        XCTAssertNil(rumContext["_dd.action.id"] as Any?)
    }

    func testItIngnoresRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: false)
        var ids: [String: String?] = .mockRandom()

        let core = PassthroughCoreMock(
            context: .mockWith(featuresAttributes: ["rum": ["ids": ids]]),
            messageReceiver: receiver
        )

        XCTAssertNil(receiver.context.rum)

        // When
        ids = .mockRandom()
        core.set(feature: "rum", attributes: { ["ids": ids] })

        // Then
        XCTAssertNil(receiver.context.rum)
    }
}
