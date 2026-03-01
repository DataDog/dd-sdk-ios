/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

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
/// Thread-safe: all state reads, writes, and listener notifications are
/// serialized through a single lock to guarantee listeners observe transitions
/// in the same order they are applied.
internal final class FlagsStateManager: FlagsStateObservable {
    /// Guards both `_state` and `_listeners` to ensure atomic state + notify.
    private let lock = NSRecursiveLock()

    private var _state: FlagsClientState = .notReady
    private var _listeners: [WeakListener] = []

    var currentState: FlagsClientState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    func updateState(_ newState: FlagsClientState) {
        lock.lock()
        defer { lock.unlock() }
        guard newState != _state else {
            return
        }
        _state = newState
        for weakListener in _listeners {
            weakListener.value?.flagsStateDidChange(newState)
        }
    }

    func addListener(_ listener: FlagsStateListener) {
        lock.lock()
        defer { lock.unlock() }
        _listeners.removeAll { $0.value == nil }
        _listeners.append(WeakListener(listener))
        listener.flagsStateDidChange(_state)
    }

    func removeListener(_ listener: FlagsStateListener) {
        lock.lock()
        _listeners.removeAll { $0.value === listener || $0.value == nil }
        lock.unlock()
    }
}

/// A weak wrapper around `FlagsStateListener` to avoid retain cycles.
private struct WeakListener {
    weak var value: FlagsStateListener?

    init(_ value: FlagsStateListener) {
        self.value = value
    }
}
