/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class FlagsStateManagerTests: XCTestCase {
    func testInitialStateIsNotReady() {
        let manager = FlagsStateManager()
        XCTAssertEqual(manager.currentState, .notReady)
    }

    func testUpdateState() {
        let manager = FlagsStateManager()

        manager.updateState(.reconciling)
        XCTAssertEqual(manager.currentState, .reconciling)

        manager.updateState(.ready)
        XCTAssertEqual(manager.currentState, .ready)

        manager.updateState(.stale)
        XCTAssertEqual(manager.currentState, .stale)

        manager.updateState(.error)
        XCTAssertEqual(manager.currentState, .error)

        manager.updateState(.notReady)
        XCTAssertEqual(manager.currentState, .notReady)
    }

    func testListenerReceivesCurrentStateOnAdd() {
        let manager = FlagsStateManager()
        manager.updateState(.ready)

        let listener = MockStateListener()
        manager.addListener(listener)

        XCTAssertEqual(listener.states, [.ready])
    }

    func testListenerReceivesStateChanges() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        // Listener receives initial state on add
        XCTAssertEqual(listener.states, [.notReady])

        manager.updateState(.reconciling)
        manager.updateState(.ready)

        XCTAssertEqual(listener.states, [.notReady, .reconciling, .ready])
    }

    func testRemoveListenerStopsNotifications() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        // Receives initial state
        XCTAssertEqual(listener.states, [.notReady])

        manager.removeListener(listener)
        manager.updateState(.ready)

        // Should not receive .ready
        XCTAssertEqual(listener.states, [.notReady])
    }

    func testMultipleListenersReceiveUpdates() {
        let manager = FlagsStateManager()
        let listener1 = MockStateListener()
        let listener2 = MockStateListener()

        manager.addListener(listener1)
        manager.addListener(listener2)

        manager.updateState(.stale)

        XCTAssertEqual(listener1.states, [.notReady, .stale])
        XCTAssertEqual(listener2.states, [.notReady, .stale])
    }

    func testDuplicateStateUpdateDoesNotNotifyListeners() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        // Listener receives initial state on add
        XCTAssertEqual(listener.states, [.notReady])

        manager.updateState(.reconciling)
        manager.updateState(.reconciling) // duplicate — should be ignored

        XCTAssertEqual(listener.states, [.notReady, .reconciling])
    }

    func testDeallocatedListenerIsCleanedUp() {
        let manager = FlagsStateManager()
        var listener: MockStateListener? = MockStateListener()
        manager.addListener(listener!)

        listener = nil // Deallocate

        // Adding a new listener should clean up the deallocated one without crash
        let newListener = MockStateListener()
        manager.addListener(newListener)

        manager.updateState(.ready)
        XCTAssertEqual(newListener.states, [.notReady, .ready])
    }

    func testListenerCanCallBackIntoManagerWithoutDeadlock() {
        // Verify that listeners can safely call manager methods from within callbacks.
        let manager = FlagsStateManager()
        let listener = ReentrantMockStateListener(manager: manager)
        manager.addListener(listener)

        manager.updateState(.ready)

        XCTAssertEqual(listener.statesObserved, [.notReady, .ready])
        XCTAssertEqual(listener.currentStatesRead, [.notReady, .ready])
    }

    func testConcurrentUpdatesAreThreadSafe() {
        // Verify thread safety under concurrent load.
        // Note: Strict ordering of notifications is not guaranteed for concurrent updates,
        // but this is acceptable because concurrent state updates don't occur in production
        // (FlagsRepository operations are sequential).
        let manager = FlagsStateManager()
        let listener = ConcurrentMockStateListener()
        manager.addListener(listener)

        // Clear the initial .notReady notification
        listener.reset()

        let iterations = 1_000
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        // Fire many concurrent state updates alternating between two states
        for i in 0..<iterations {
            group.enter()
            queue.async {
                let state: FlagsClientState = i % 2 == 0 ? .reconciling : .ready
                manager.updateState(state)
                group.leave()
            }
        }

        group.wait()

        // Verify thread safety: no crashes occurred and notifications were received.
        // Final state should be one of the alternating states.
        let observed = listener.observedStates
        XCTAssertGreaterThan(observed.count, 0, "Should have received state notifications")

        let finalState = manager.currentState
        XCTAssertTrue(
            finalState == .reconciling || finalState == .ready,
            "Final state should be one of the alternating states"
        )

        // All observed states should be valid (either .reconciling or .ready)
        for state in observed {
            XCTAssertTrue(
                state == .reconciling || state == .ready,
                "All observed states should be .reconciling or .ready, got \(state)"
            )
        }
    }
    // A caller can release its own lock in a different order than it acquired it, so a deferred
    // delivery can run after a newer one. The stale delivery must be dropped, otherwise a
    // listener's last callback disagrees with `currentState`.
    // Delivery happens outside the lock, so the closures can run in either order. Whichever runs
    // must report the newest state, or a listener's last callback disagrees with `currentState`.
    func testDeferredNotificationInvokedOutOfOrderStillReportsNewestState() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        let staleDelivery = manager.updateStateDeferringNotification(.reconciling)
        let newestDelivery = manager.updateStateDeferringNotification(.ready)

        staleDelivery()
        newestDelivery()

        XCTAssertEqual(manager.currentState, .ready)
        XCTAssertEqual(listener.states.last, .ready)
        XCTAssertFalse(
            listener.states.contains(.reconciling),
            "a delivery must report currentState, not the transition it was created for"
        )
        XCTAssertEqual(
            listener.states.filter { $0 == .ready }.count,
            1,
            "the second delivery must be a no-op once the newest state was reported"
        )
    }

    func testStaleDeferredNotificationIsSuppressed() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        let staleDelivery = manager.updateStateDeferringNotification(.reconciling)
        let newestDelivery = manager.updateStateDeferringNotification(.ready)

        newestDelivery()
        staleDelivery()

        XCTAssertEqual(manager.currentState, .ready)
        XCTAssertEqual(
            listener.states.last,
            .ready,
            "a listener's last callback must equal currentState"
        )
        XCTAssertFalse(
            listener.states.contains(.reconciling),
            "the superseded transition must not be delivered after the newer one"
        )
    }

    func testDeferredNotificationsDeliveredInOrderAreAllSeen() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)

        manager.updateStateDeferringNotification(.reconciling)()
        manager.updateStateDeferringNotification(.ready)()

        XCTAssertEqual(listener.states, [.notReady, .reconciling, .ready])
        XCTAssertEqual(manager.currentState, .ready)
    }

    func testDeferredNotificationForUnchangedStateDeliversNothing() {
        let manager = FlagsStateManager()
        let listener = MockStateListener()
        manager.addListener(listener)
        let before = listener.states.count

        manager.updateStateDeferringNotification(.notReady)()

        XCTAssertEqual(listener.states.count, before)
    }
}

// MARK: - Helpers

private final class MockStateListener: FlagsStateListener {
    var states: [FlagsClientState] = []

    func flagsStateDidChange(_ newState: FlagsClientState) {
        states.append(newState)
    }
}

/// Listener that calls back into the manager to verify reentrant access is safe.
private final class ReentrantMockStateListener: FlagsStateListener {
    private let manager: FlagsStateManager
    var statesObserved: [FlagsClientState] = []
    var currentStatesRead: [FlagsClientState] = []

    init(manager: FlagsStateManager) {
        self.manager = manager
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        statesObserved.append(newState)
        currentStatesRead.append(manager.currentState)
    }
}

/// Thread-safe listener for concurrency tests.
private final class ConcurrentMockStateListener: FlagsStateListener {
    private let lock = NSLock()
    private var _states: [FlagsClientState] = []

    var observedStates: [FlagsClientState] {
        lock.lock()
        defer { lock.unlock() }
        return _states
    }

    func reset() {
        lock.lock()
        _states.removeAll()
        lock.unlock()
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        lock.lock()
        _states.append(newState)
        lock.unlock()
    }
}
