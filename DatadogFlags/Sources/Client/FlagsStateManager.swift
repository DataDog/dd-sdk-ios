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

    @ReadWriteLock
    private var managerState = ManagerState()

    var currentState: FlagsClientState {
        managerState.clientState
    }

    func updateState(_ newState: FlagsClientState) {
        // Capture listeners under lock, then notify outside lock to prevent deadlock.
        var listenersToNotify: [WeakListener] = []

        _managerState.mutate { state in
            guard newState != state.clientState else {
                return
            }
            state.clientState = newState
            listenersToNotify = state.listeners
        }

        for weakListener in listenersToNotify {
            weakListener.value?.flagsStateDidChange(newState)
        }
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
