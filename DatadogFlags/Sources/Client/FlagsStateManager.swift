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
        /// Increments on every state change, so a deferred delivery can tell whether it is stale.
        var transition: UInt64 = 0
        /// The newest transition already delivered to listeners.
        var deliveredTransition: UInt64 = 0
    }

    @ReadWriteLock
    private var managerState = ManagerState()

    var currentState: FlagsClientState {
        managerState.clientState
    }

    func updateState(_ newState: FlagsClientState) {
        updateStateDeferringNotification(newState)()
    }

    /// Publishes `newState` and returns a closure that notifies its listeners.
    ///
    /// A caller holding its own lock must invoke the returned closure only after unlocking.
    /// Listeners are customer code and may re-enter the SDK.
    /// Callers can release their lock in a different order than they acquired it, so the returned
    /// closure reports whichever state is current when it runs, and does nothing if a later
    /// delivery already reported it. This keeps a listener's last callback equal to `currentState`
    /// without holding any lock while customer code runs.
    ///
    /// The caller must invoke the returned closure exactly once, after releasing its own lock.
    func updateStateDeferringNotification(
        _ newState: FlagsClientState
    ) -> () -> Void {
        var didChange = false

        _managerState.mutate { state in
            guard newState != state.clientState else {
                return
            }
            state.transition &+= 1
            state.clientState = newState
            didChange = true
        }

        guard didChange else {
            return {}
        }

        return { [weak self] in
            guard let self else {
                return
            }
            // Capture listeners under lock, then notify outside lock to prevent deadlock.
            var stateToDeliver: FlagsClientState?
            var listenersToNotify: [WeakListener] = []
            var transitionToDeliver: UInt64 = 0
            self._managerState.mutate { state in
                guard state.deliveredTransition != state.transition else {
                    return
                }
                state.deliveredTransition = state.transition
                transitionToDeliver = state.transition
                stateToDeliver = state.clientState
                listenersToNotify = state.listeners
            }
            guard let stateToDeliver else {
                return
            }
            for weakListener in listenersToNotify {
                // A listener can change the state from inside this callback, and that newer
                // delivery reaches every listener. This one is stale from that point on, so it
                // stops rather than follow the newer state with an older one.
                guard self.managerState.deliveredTransition == transitionToDeliver else {
                    return
                }
                weakListener.value?.flagsStateDidChange(stateToDeliver)
            }
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
