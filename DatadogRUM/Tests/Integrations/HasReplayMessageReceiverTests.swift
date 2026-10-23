/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities
@testable import DatadogRUM

class HasReplayMessageReceiverTests: XCTestCase {
    private let receiver = HasReplayMessageReceiver()

    private func contextMessage(sessionID: UUID, hasReplay: Bool?) -> FeatureMessage {
        var additionalContext: [any AdditionalContext] = [RUMCoreContext.mockWith(sessionID: sessionID)]
        if let hasReplay = hasReplay {
            additionalContext.append(SessionReplayCoreContext.HasReplay(value: hasReplay))
        }
        return .context(.mockWith(additionalContext: additionalContext))
    }

    func testItTracksReplayStatePerSession() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let firstID = first.uuidString.lowercased()
        let secondID = second.uuidString.lowercased()

        // When — a context message carries replay baggage for the active session
        _ = receiver.receive(message: contextMessage(sessionID: first, hasReplay: true), from: NOPDatadogCore())

        // Then
        XCTAssertEqual(receiver.hasReplay(sessionID: firstID), true)

        // When — a later context message of the same session carries no replay baggage
        _ = receiver.receive(message: contextMessage(sessionID: first, hasReplay: nil), from: NOPDatadogCore())

        // Then — the state is cleared
        XCTAssertNil(receiver.hasReplay(sessionID: firstID))

        // When — the first session reports replay, then a new session appears with that stale state attached
        receiver.update(sessionID: firstID, hasReplay: true)
        _ = receiver.receive(message: contextMessage(sessionID: second, hasReplay: true), from: NOPDatadogCore())

        // Then — the new session does not inherit it, and the previous session keeps its own
        XCTAssertNil(receiver.hasReplay(sessionID: secondID))
        XCTAssertEqual(receiver.hasReplay(sessionID: firstID), true)

        // When — the new session reports replay again
        _ = receiver.receive(message: contextMessage(sessionID: second, hasReplay: true), from: NOPDatadogCore())

        // Then — it is taken as reported
        XCTAssertEqual(receiver.hasReplay(sessionID: secondID), true)

        // When — a third session appears
        _ = receiver.receive(message: contextMessage(sessionID: third, hasReplay: false), from: NOPDatadogCore())

        // Then — only the last two sessions are retained
        XCTAssertNil(receiver.hasReplay(sessionID: firstID))
        XCTAssertEqual(receiver.hasReplay(sessionID: secondID), true)
    }

    func testItDoesNotConsumeNonContextMessages() {
        let result = receiver.receive(message: .payload("not-a-context-message"), from: NOPDatadogCore())
        XCTAssertFalse(result)
    }
}
