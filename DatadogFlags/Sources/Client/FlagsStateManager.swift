/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A listener that receives state change notifications from a ``FlagsClient``.
///
/// Implement this protocol to observe state transitions. Listeners are called
/// synchronously after the state is updated, so implementations should be
/// fast and non-blocking.
public protocol FlagsStateListener: AnyObject {
    /// Called when the client state changes.
    ///
    /// - Parameter newState: The new state of the client.
    func flagsStateDidChange(_ newState: FlagsClientState)
}

/// An observable interface for tracking ``FlagsClient`` state changes.
public protocol FlagsStateObservable: AnyObject {
    /// The current state of the client.
    var currentState: FlagsClientState { get }

    /// Registers a listener that receives state change notifications.
    ///
    /// The listener is immediately called with the current state upon registration.
    ///
    /// - Parameter listener: The listener to register. Held weakly.
    func addListener(_ listener: FlagsStateListener)

    /// Removes a previously registered listener.
    ///
    /// - Parameter listener: The listener to remove.
    func removeListener(_ listener: FlagsStateListener)
}

/// Manages state transitions and listener notifications for a ``FlagsClient``.
///
/// Thread-safe: state reads and writes are synchronized using a read-write lock.
/// Listener notifications are performed outside the lock to prevent deadlocks
/// when listeners call back into the manager.
internal final class FlagsStateManager: FlagsStateObservable {
    /// Groups state and listeners for atomic access.
    private struct ManagerState {
        var clientState: FlagsClientState = .notReady
        var listeners: [WeakListener] = []
    }

    private static func logStateDiagnostic(_ message: String, startedAt: Date, details: String? = nil) {
        let now = Date()
        let elapsedMs = now.timeIntervalSince(startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        let details = details.map { " \($0)" } ?? ""
        print(
            "Datadog Flags state manager \(message)\(details) at \(now.timeIntervalSince1970) elapsedMs=\(elapsedMs) thread=\(thread)"
        )
    }

    @ReadWriteLock
    private var managerState = ManagerState()

    var currentState: FlagsClientState {
        managerState.clientState
    }

    func updateState(_ newState: FlagsClientState) {
        let startedAt = Date()
        Self.logStateDiagnostic("updateState start", startedAt: startedAt, details: "newState=\(newState)")

        // Capture listeners under lock, then notify outside lock to prevent deadlock.
        var listenersToNotify: [WeakListener] = []
        var previousState: FlagsClientState = .notReady
        var didUpdate = false

        _managerState.mutate { state in
            previousState = state.clientState
            guard newState != state.clientState else {
                return
            }
            state.clientState = newState
            listenersToNotify = state.listeners
            didUpdate = true
        }

        Self.logStateDiagnostic(
            "updateState mutate end",
            startedAt: startedAt,
            details: "previousState=\(previousState) newState=\(newState) didUpdate=\(didUpdate) listenerCount=\(listenersToNotify.count)"
        )

        guard didUpdate else {
            return
        }

        Self.logStateDiagnostic("updateState listeners notify start", startedAt: startedAt)
        for (index, weakListener) in listenersToNotify.enumerated() {
            guard let listener = weakListener.value else {
                Self.logStateDiagnostic(
                    "updateState listener skipped",
                    startedAt: startedAt,
                    details: "index=\(index) reason=deallocated"
                )
                continue
            }

            Self.logStateDiagnostic("updateState listener notify start", startedAt: startedAt, details: "index=\(index)")
            listener.flagsStateDidChange(newState)
            Self.logStateDiagnostic("updateState listener notify end", startedAt: startedAt, details: "index=\(index)")
        }
        Self.logStateDiagnostic("updateState listeners notify end", startedAt: startedAt)
    }

    func addListener(_ listener: FlagsStateListener) {
        // Capture current state under lock, then notify outside lock.
        var currentStateForNotification: FlagsClientState = .notReady

        _managerState.mutate { state in
            state.listeners.removeAll { $0.value == nil }
            state.listeners.append(WeakListener(listener))
            currentStateForNotification = state.clientState
        }

        listener.flagsStateDidChange(currentStateForNotification)
    }

    func removeListener(_ listener: FlagsStateListener) {
        _managerState.mutate { state in
            state.listeners.removeAll { $0.value === listener || $0.value == nil }
        }
    }
}

/// A weak wrapper around `FlagsStateListener` to avoid retain cycles.
private struct WeakListener {
    weak var value: FlagsStateListener?

    init(_ value: FlagsStateListener) {
        self.value = value
    }
}

/// A no-op observable that always reports a fixed state.
/// Used for fallback clients where state management is not needed.
internal final class NOPStateObservable: FlagsStateObservable {
    /// Shared instance for the `notReady` state.
    static let notReady = NOPStateObservable(state: .notReady)

    /// Shared instance for the `error` state.
    static let error = NOPStateObservable(state: .error)

    let currentState: FlagsClientState

    private init(state: FlagsClientState) {
        self.currentState = state
    }

    func addListener(_ listener: FlagsStateListener) {
        listener.flagsStateDidChange(currentState)
    }

    func removeListener(_ listener: FlagsStateListener) {
        // No-op: listeners are not tracked
    }
}
