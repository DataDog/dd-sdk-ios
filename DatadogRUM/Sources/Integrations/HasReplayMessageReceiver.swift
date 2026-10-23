/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Owns the Session Replay state of the last `maxRetainedSessions` RUM sessions, keyed by session ID.
///
/// It is fed by the core's context message bus, so it stays current even when Session Replay starts/stops with no
/// `RUMCommand` processed around the same time.
/// Safe to read and update from any thread.
internal final class HasReplayMessageReceiver: FeatureMessageReceiver {
    private static let maxRetainedSessions = 2

    @ReadWriteLock
    private var states: [(sessionID: String, hasReplay: Bool?)] = []

    /// Whether replay was reported active at any point during `sessionID`, or `nil` if no replay state was reported for it.
    func hasReplay(sessionID: String) -> Bool? {
        states.first { $0.sessionID == sessionID }?.hasReplay
    }

    /// Records the replay state reported for `sessionID`, OR-accumulated so a later report of replay stopping does not
    /// erase it before a pending flush reads it (mirrors `RUMViewScope`).
    ///
    /// The first report of a session after another one is ignored, because Session Replay has not recomputed its
    /// decision for the new session yet, so the value still belongs to the previous one.
    func update(sessionID: String, hasReplay: Bool?) {
        _states.mutate { states in
            if let index = states.firstIndex(where: { $0.sessionID == sessionID }) {
                if let hasReplay = hasReplay {
                    states[index].hasReplay = (states[index].hasReplay ?? false) || hasReplay
                }
            } else {
                states.append((sessionID, states.isEmpty ? hasReplay : nil))
                states = Array(states.suffix(Self.maxRetainedSessions))
            }
        }
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              let sessionID = context.additionalContext(ofType: RUMCoreContext.self)?.sessionID else {
            return false
        }

        update(sessionID: sessionID, hasReplay: context.hasReplay)

        return false
    }
}
