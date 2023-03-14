/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import Datadog

class ContextMessageReceiverTests: XCTestCase {
    func testItReceivesApplicationStateHistory() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRUM: .mockRandom())
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
        let receiver = ContextMessageReceiver(bundleWithRUM: true)
        let core = PassthroughCoreMock(
            context: .mockWith(featuresAttributes: ["rum": ["ids": ["key": "value1"]]]),
            messageReceiver: receiver
        )

        XCTAssertEqual(receiver.context.rum, ["key": "value1"])

        // When
        core.set(feature: "rum", attributes: { ["ids": ["key": "value2"]] })

        // Then
        XCTAssertEqual(receiver.context.rum, ["key": "value2"])
    }

    func testItIngnoresRUMContext() throws {
        // Given
        let receiver = ContextMessageReceiver(bundleWithRUM: false)
        let core = PassthroughCoreMock(
            context: .mockWith(featuresAttributes: ["rum": ["ids": ["key": "value1"]]]),
            messageReceiver: receiver
        )

        XCTAssertNil(receiver.context.rum)

        // When
        core.set(feature: "rum", attributes: { ["ids": ["key": "value2"]] })

        // Then
        XCTAssertNil(receiver.context.rum)
    }
}
