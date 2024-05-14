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
    private let featureScope = FeatureScopeMock()

    // MARK: - Changing Session State

    func testWhenSessionStateIsSet_itSendsSessionStateMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: featureScope)
        let newSessionState: RUMSessionState = .mockRandom()

        // When
        fatalErrorContext.sessionState = newSessionState

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1)
        let sessionStateMessage = try XCTUnwrap(messages.lastBaggage(withKey: RUMBaggageKeys.sessionState))
        XCTAssertEqual(newSessionState, try sessionStateMessage.decode())
    }

    func testWhenSessionStateIsReset_itDoesNotSendNextSessionStateMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: featureScope)
        let originalSessionState: RUMSessionState = .mockRandom()
        fatalErrorContext.sessionState = originalSessionState

        // When
        fatalErrorContext.sessionState = nil

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1)
        let sessionStateMessage = try XCTUnwrap(messages.lastBaggage(withKey: RUMBaggageKeys.sessionState))
        XCTAssertEqual(originalSessionState, try sessionStateMessage.decode())
    }

    // MARK: - Changing View State

    func testWhenViewIsSet_itSendsViewEventMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: featureScope)
        let newViewEvent: RUMViewEvent = .mockRandom()

        // When
        fatalErrorContext.view = newViewEvent

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1)
        let viewEventMessage = try XCTUnwrap(messages.lastBaggage(withKey: RUMBaggageKeys.viewEvent))
        DDAssertJSONEqual(newViewEvent, try viewEventMessage.decode(type: RUMViewEvent.self))
    }

    func testWhenViewIsReset_itSendsViewResetMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: featureScope)
        fatalErrorContext.view = .mockRandom()

        // When
        fatalErrorContext.view = nil

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 2)
        let viewResetMessage = try XCTUnwrap(messages.lastBaggage(withKey: RUMBaggageKeys.viewReset))
        XCTAssertTrue(try viewResetMessage.decode(type: Bool.self))
    }
}
