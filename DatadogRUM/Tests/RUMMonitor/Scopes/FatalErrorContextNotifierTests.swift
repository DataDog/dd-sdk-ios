/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class FatalErrorContextNotifierTests: XCTestCase {
    private let bus = PassthroughCoreMock()

    // MARK: - Changing Session State

    func testWhenSessionStateIsSet_itSendsSessionStateMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var received: [RUMSessionState] = []
        _ = bus.subscribe { (state: RUMSessionState, _) in received.append(state) }
        let newSessionState: RUMSessionState = .mockRandom()

        // When
        fatalErrorContext.sessionState = newSessionState

        // Then
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first, newSessionState)
    }

    func testWhenSessionStateIsReset_itDoesNotSendNextSessionStateMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var received: [RUMSessionState] = []
        _ = bus.subscribe { (state: RUMSessionState, _) in received.append(state) }
        let originalSessionState: RUMSessionState = .mockRandom()
        fatalErrorContext.sessionState = originalSessionState

        // When
        fatalErrorContext.sessionState = nil

        // Then
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first, originalSessionState)
    }

    // MARK: - Changing View State

    func testWhenViewIsSet_itSendsViewEventMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var receivedViews: [RUMViewEvent] = []
        _ = bus.subscribe { (event: RUMViewEvent, _) in receivedViews.append(event) }
        let newViewEvent: RUMViewEvent = .mockRandom()

        // When
        fatalErrorContext.view = newViewEvent

        // Then
        XCTAssertEqual(receivedViews.count, 1)
        DDAssertJSONEqual(receivedViews.first, newViewEvent)
    }

    func testWhenViewIsReset_itSendsViewResetMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var resetCount = 0
        _ = bus.subscribe { (_: RUMViewReset, _) in resetCount += 1 }
        fatalErrorContext.view = .mockRandom()

        // When
        fatalErrorContext.view = nil

        // Then
        XCTAssertEqual(resetCount, 1)
    }

    // MARK: - Changing Global Attributes

    func testWhenGlobalAttributesAreSet_itSendsAttributesMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var received: [RUMEventAttributes] = []
        _ = bus.subscribe { (attrs: RUMEventAttributes, _) in received.append(attrs) }
        let newGlobalAttributes = mockRandomAttributes()

        // When
        fatalErrorContext.globalAttributes = newGlobalAttributes

        // Then
        XCTAssertEqual(received.count, 1)
        DDAssertJSONEqual(received.first, newGlobalAttributes)
    }
}
