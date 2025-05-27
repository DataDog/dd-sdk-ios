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
        let sessionStateMessage = try XCTUnwrap(messages.lastPayload as? RUMSessionState)
        XCTAssertEqual(newSessionState, sessionStateMessage)
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
        let sessionStateMessage = try XCTUnwrap(messages.lastPayload as? RUMSessionState)
        XCTAssertEqual(originalSessionState, sessionStateMessage)
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
        let viewEventMessage = try XCTUnwrap(messages.firstPayload as? RUMViewEvent)
        DDAssertJSONEqual(newViewEvent, viewEventMessage)
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
        let viewEventMessage = try XCTUnwrap(messages.lastPayload as? String)
        XCTAssertEqual(viewEventMessage, RUMPayloadMessages.viewReset)
    }

    // MARK: - Changing Global Attributes

    func testWhenGlobalAttributesAreSet_itSendsAttributesMessage() throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifier(messageBus: featureScope)
        let newGlobalAttributes = mockRandomAttributes()

        // When
        fatalErrorContext.globalAttributes = newGlobalAttributes

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1)
        let attributesMessage = try XCTUnwrap(messages.lastPayload as? RUMEventAttributes)
        DDAssertJSONEqual(newGlobalAttributes, attributesMessage)
    }
}
