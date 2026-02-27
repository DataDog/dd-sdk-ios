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
/// synchronously while holding an internal lock, so implementations should be
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
/// Thread-safe: all state reads and writes are protected by a read-write lock.
internal final class FlagsStateManager: FlagsStateObservable {
    @ReadWriteLock
    private var state: FlagsClientState = .notReady

    @ReadWriteLock
    private var listeners: [WeakListener] = []

    var currentState: FlagsClientState {
        state
    }

    func updateState(_ newState: FlagsClientState) {
        _state.mutate { state in
            state = newState
        }
        notifyListeners(newState)
    }

    func addListener(_ listener: FlagsStateListener) {
        _listeners.mutate { listeners in
            listeners.removeAll { $0.value == nil }
            listeners.append(WeakListener(listener))
        }
        listener.flagsStateDidChange(state)
    }

    func removeListener(_ listener: FlagsStateListener) {
        _listeners.mutate { listeners in
            listeners.removeAll { $0.value === listener || $0.value == nil }
        }
    }

    private func notifyListeners(_ newState: FlagsClientState) {
        let currentListeners = _listeners.wrappedValue
        for weakListener in currentListeners {
            weakListener.value?.flagsStateDidChange(newState)
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
