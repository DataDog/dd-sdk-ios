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
    // MARK: - Changing Session State

    func testWhenSessionStateIsSet_itSendsSessionStateMessage() throws {
        // Given
        let core = NOPDatadogCore()
        let bus = PassthroughMessageBusMock(core: core)
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        let newSessionState: RUMSessionState = .mockRandom()
        var received: RUMSessionState?
        let subscription = bus.subscribe { (message: RUMSessionState, _) in received = message }

        // When
        fatalErrorContext.sessionState = newSessionState

        // Then
        XCTAssertEqual(received, newSessionState)
        _ = subscription
    }

    func testWhenSessionStateIsReset_itDoesNotSendNextSessionStateMessage() throws {
        // Given
        let core = NOPDatadogCore()
        let bus = PassthroughMessageBusMock(core: core)
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var receiveCount = 0
        let subscription = bus.subscribe { (_: RUMSessionState, _) in receiveCount += 1 }
        fatalErrorContext.sessionState = .mockRandom()

        // When
        fatalErrorContext.sessionState = nil

        // Then
        XCTAssertEqual(receiveCount, 1)
        _ = subscription
    }

    // MARK: - Changing View State

    func testWhenViewIsSet_itSendsViewEventMessage() throws {
        // Given
        let core = NOPDatadogCore()
        let bus = PassthroughMessageBusMock(core: core)
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        let newViewEvent: RUMViewEvent = .mockRandom()
        var received: RUMViewEvent?
        let subscription = bus.subscribe { (message: RUMViewEvent, _) in received = message }

        // When
        fatalErrorContext.view = newViewEvent

        // Then
        let receivedView = try XCTUnwrap(received)
        DDAssertJSONEqual(newViewEvent, receivedView)
        _ = subscription
    }

    func testWhenViewIsReset_itSendsViewResetMessage() throws {
        // Given
        let core = NOPDatadogCore()
        let bus = PassthroughMessageBusMock(core: core)
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        var viewResetCount = 0
        let subscription = bus.subscribe { (_: RUMViewResetMessage, _) in viewResetCount += 1 }
        fatalErrorContext.view = .mockRandom()

        // When
        fatalErrorContext.view = nil

        // Then
        XCTAssertEqual(viewResetCount, 1)
        _ = subscription
    }

    // MARK: - Changing Global Attributes

    func testWhenGlobalAttributesAreSet_itSendsAttributesMessage() throws {
        // Given
        let core = NOPDatadogCore()
        let bus = PassthroughMessageBusMock(core: core)
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: bus)
        let newGlobalAttributes = mockRandomAttributes()
        var received: RUMEventAttributes?
        let subscription = bus.subscribe { (message: RUMEventAttributes, _) in received = message }

        // When
        fatalErrorContext.globalAttributes = newGlobalAttributes

        // Then
        let receivedAttributes = try XCTUnwrap(received)
        DDAssertJSONEqual(newGlobalAttributes, receivedAttributes)
        _ = subscription
    }
}
