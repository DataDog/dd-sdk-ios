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

    func testConcurrentUpdatesDeliverStatesInOrder() {
        let manager = FlagsStateManager()
        let listener = ConcurrentMockStateListener()
        manager.addListener(listener)

        // Clear the initial .notReady notification
        listener.reset()

        let iterations = 1000
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

        // Verify: each observed state must differ from its predecessor
        // (no duplicate consecutive states, which would indicate out-of-order delivery
        // where a stale notification arrived after a newer one)
        let observed = listener.observedStates
        for i in 1..<observed.count {
            XCTAssertNotEqual(
                observed[i], observed[i - 1],
                "Listener received duplicate consecutive state at index \(i): \(observed[i])"
            )
        }
    }
}

// MARK: - Helpers

private final class MockStateListener: FlagsStateListener {
    var states: [FlagsClientState] = []

    func flagsStateDidChange(_ newState: FlagsClientState) {
        states.append(newState)
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
