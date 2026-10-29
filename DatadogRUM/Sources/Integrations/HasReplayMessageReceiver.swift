/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Owns the Session Replay state of the last `maxRetainedSessions` RUM sessions, keyed by the session ID Session Replay
/// computed each value for, so a value computed for a previous session is never recorded for the current one.
///
/// It is fed by the core's context message bus, so it stays current even when Session Replay starts/stops with no
/// `RUMCommand` processed around the same time, and by `Monitor` with the context of each command, so a command that
/// ends or pauses a session records what it sees before the collector flushes.
/// Safe to read and update from any thread.
internal final class HasReplayMessageReceiver: FeatureMessageReceiver {
    private static let maxRetainedSessions = 2

    @ReadWriteLock
    private var states: [(sessionID: String, hasReplay: Bool)] = []

    /// Whether replay was reported active at any point during `sessionID`, or `nil` if no replay state was reported for it.
    func hasReplay(sessionID: String) -> Bool? {
        states.first { $0.sessionID == sessionID }?.hasReplay
    }

    /// Records the replay state Session Replay reported in `context`, for the session it was computed for.
    /// Values not computed for a RUM session are ignored.
    func update(from context: DatadogContext) {
        guard let replay = context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self),
              let sessionID = replay.sessionID else {
            return
        }

        update(sessionID: sessionID, hasReplay: replay.value)
    }

    /// Records the replay state reported for `sessionID`, OR-accumulated so a later report of replay stopping does not
    /// erase it before a pending flush reads it (mirrors `RUMViewScope`).
    func update(sessionID: String, hasReplay: Bool) {
        _states.mutate { states in
            if let index = states.firstIndex(where: { $0.sessionID == sessionID }) {
                states[index].hasReplay = states[index].hasReplay || hasReplay
            } else {
                states.append((sessionID, hasReplay))
                states = Array(states.suffix(Self.maxRetainedSessions))
            }
        }
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        update(from: context)

        return false
    }
}
