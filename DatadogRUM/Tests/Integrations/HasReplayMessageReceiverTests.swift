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

    private func contextMessage(sessionID: UUID, hasReplay: Bool?, replaySessionID: String?) -> FeatureMessage {
        var additionalContext: [any AdditionalContext] = [RUMCoreContext.mockWith(sessionID: sessionID)]
        if let hasReplay = hasReplay {
            additionalContext.append(SessionReplayCoreContext.HasReplay(value: hasReplay, sessionID: replaySessionID))
        }
        return .context(.mockWith(additionalContext: additionalContext))
    }

    func testItTracksReplayStatePerSession() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let firstID = first.uuidString.lowercased()
        let secondID = second.uuidString.lowercased()

        // When — a context message carries replay baggage computed for the active session
        _ = receiver.receive(message: contextMessage(sessionID: first, hasReplay: true, replaySessionID: firstID), from: NOPDatadogCore())

        // Then
        XCTAssertEqual(receiver.hasReplay(sessionID: firstID), true)

        // When — later context messages of the same session report replay stopped, or carry no replay baggage
        _ = receiver.receive(message: contextMessage(sessionID: first, hasReplay: false, replaySessionID: firstID), from: NOPDatadogCore())
        _ = receiver.receive(message: contextMessage(sessionID: first, hasReplay: nil, replaySessionID: nil), from: NOPDatadogCore())

        // Then — the session keeps reporting replay, so a flush still pending for it does not lose it
        XCTAssertEqual(receiver.hasReplay(sessionID: firstID), true)

        // When — a new session starts while the replay baggage is still the one computed for the first session
        _ = receiver.receive(message: contextMessage(sessionID: second, hasReplay: false, replaySessionID: firstID), from: NOPDatadogCore())

        // Then — the new session does not inherit it, and the previous session keeps its own
        XCTAssertNil(receiver.hasReplay(sessionID: secondID))
        XCTAssertEqual(receiver.hasReplay(sessionID: firstID), true)

        // When — replay baggage is not attributed to any session
        _ = receiver.receive(message: contextMessage(sessionID: second, hasReplay: true, replaySessionID: nil), from: NOPDatadogCore())

        // Then — it is ignored
        XCTAssertNil(receiver.hasReplay(sessionID: secondID))

        // When — Session Replay reports replay computed for the new session
        _ = receiver.receive(message: contextMessage(sessionID: second, hasReplay: true, replaySessionID: secondID), from: NOPDatadogCore())

        // Then — it is taken as reported
        XCTAssertEqual(receiver.hasReplay(sessionID: secondID), true)

        // When — a third session appears
        _ = receiver.receive(message: contextMessage(sessionID: third, hasReplay: false, replaySessionID: third.uuidString.lowercased()), from: NOPDatadogCore())

        // Then — only the last two sessions are retained
        XCTAssertNil(receiver.hasReplay(sessionID: firstID))
        XCTAssertEqual(receiver.hasReplay(sessionID: secondID), true)
    }

    func testItDoesNotConsumeNonContextMessages() {
        let result = receiver.receive(message: .payload("not-a-context-message"), from: NOPDatadogCore())
        XCTAssertFalse(result)
    }
}
