/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

private extension AppState {
    static var randomForeground: AppState {
        return [.active, .inactive].randomElement()!
    }
}

class AppStateHistoryTests: XCTestCase {
    private let date = Date()

    func testItBuildsAppStateFromUIApplicationState() {
        XCTAssertEqual(AppState(.active), .active)
        XCTAssertEqual(AppState(.inactive), .inactive)
        XCTAssertEqual(AppState(.background), .background)
    }

    // MARK: - `currentState`

    func testCurrentState_whenOnlyInitialState() {
        // Given
        let state: AppState = .mockRandom()
        let history = AppStateHistory(initialState: state, date: date)

        // Then
        XCTAssertEqual(history.currentState, state)
    }

    func testCurrentState_afterStateChanges() {
        // Given
        var history = AppStateHistory(initialState: .active, date: date)

        // When / Then
        history.append(state: .inactive, at: date + 1)
        XCTAssertEqual(history.currentState, .inactive)

        history.append(state: .background, at: date + 2)
        XCTAssertEqual(history.currentState, .background)

        history.append(state: .active, at: date + 3)
        XCTAssertEqual(history.currentState, .active)
    }

    func testCurrentState_whenTransitionsNotInChronologicalOrder() {
        // Given
        var history = AppStateHistory(initialState: .active, date: date)

        // When / Then
        history.append(state: .background, at: date - 10)
        XCTAssertEqual(history.currentState, .active, "It should always reflect chronologically latest state")

        history.append(state: .inactive, at: date + 5)
        history.append(state: .background, at: date + 2)
        XCTAssertEqual(history.currentState, .inactive, "It should always reflect chronologically latest state")
    }

    // MARK: - `state(at:)`

    func testStateAt_whenOnlyInitialState() {
        // Given
        let state: AppState = .mockRandom()
        let history = AppStateHistory(initialState: state, date: date)

        // Then
        XCTAssertEqual(history.state(at: date), state)
        XCTAssertNil(history.state(at: date - 1))
        XCTAssertEqual(history.state(at: date + 1), state)
    }

    func testStateAt_whenMultipleTransitions() {
        // Given
        var history = AppStateHistory(initialState: .inactive, date: date)

        // When
        history.append(state: .active, at: date + 10)
        history.append(state: .background, at: date + 20)
        history.append(state: .inactive, at: date + 30)

        // Then
        XCTAssertEqual(history.state(at: date), .inactive)
        XCTAssertEqual(history.state(at: date + 5), .inactive)
        XCTAssertEqual(history.state(at: date + 10), .active)
        XCTAssertEqual(history.state(at: date + 15), .active)
        XCTAssertEqual(history.state(at: date + 20), .background)
        XCTAssertEqual(history.state(at: date + 25), .background)
        XCTAssertEqual(history.state(at: date + 30), .inactive)
        XCTAssertEqual(history.state(at: date + 35), .inactive)
    }

    func testStateAt_whenOutsideRange() {
        // Given
        var history = AppStateHistory(initialState: .inactive, date: date)

        // When
        history.append(state: .active, at: date + 10)
        history.append(state: .background, at: date + 20)

        // Then
        XCTAssertNil(history.state(at: .distantPast))
        XCTAssertNil(history.state(at: date - 5))
        XCTAssertEqual(history.state(at: date + 25), .background)
        XCTAssertEqual(history.state(at: .distantFuture), .background)
    }

    func testStateAt_whenTransitionsNotInChronologicalOrder() {
        // Given
        let date = Date()
        var history = AppStateHistory(initialState: .inactive, date: date)

        // When
        let transitions: [() -> Void] = [
            { history.append(state: .active, at: date + 10) },
            { history.append(state: .background, at: date + 20) },
            { history.append(state: .inactive, at: date + 30) },
        ]
        transitions.shuffled().forEach { $0() }

        // Then
        XCTAssertEqual(history.state(at: date), .inactive)
        XCTAssertEqual(history.state(at: date + 10), .active)
        XCTAssertEqual(history.state(at: date + 20), .background)
        XCTAssertEqual(history.state(at: date + 30), .inactive)
    }

    // MARK: - `foregroundDuration(during:)`

    func testForegroundDuration_whenStartedInForegrounded() {
        // When
        let history = AppStateHistory(initialState: .randomForeground, date: date)

        // Then
        XCTAssertEqual(history.foregroundDuration(during: date...(date + 10)), 10)
    }

    func testForegroundDuration_whenAlwaysForegrounded() {
        // Given
        var history = AppStateHistory(initialState: .randomForeground, date: date)

        // When
        history.append(state: .randomForeground, at: date + 10)

        // Then
        let duration = history.foregroundDuration(during: date...(date + 10))
        XCTAssertEqual(duration, 10)
    }

    func testForegroundDuration_whenAlwaysBackgrounded() {
        // Given
        var history = AppStateHistory(initialState: .background, date: date)

        // When
        history.append(state: .background, at: date + 10)

        // Then
        let duration = history.foregroundDuration(during: date...(date + 10))
        XCTAssertEqual(duration, 0)
    }

    func testForegroundDuration_whenMultipleTransitions() {
        // Given
        var history = AppStateHistory(initialState: .background, date: date)

        // When
        history.append(state: .randomForeground, at: date + 5)
        history.append(state: .background, at: date + 10)
        history.append(state: .randomForeground, at: date + 15)

        // Then
        XCTAssertEqual(history.foregroundDuration(during: date...(date + 15)), 5)
        XCTAssertEqual(history.foregroundDuration(during: date...(date + 20)), 10)
        XCTAssertEqual(history.foregroundDuration(during: (date + 10)...(date + 15)), 0)
        XCTAssertEqual(history.foregroundDuration(during: (date + 5)...(date + 10)), 5)
    }

    func testForegroundDuration_whenOutsideRange() {
        // Given
        var history = AppStateHistory(initialState: .randomForeground, date: date)

        // When
        history.append(state: .background, at: date + 5)
        history.append(state: .randomForeground, at: date + 10)

        // Then
        XCTAssertEqual(history.foregroundDuration(during: (date - 100)...(date)), 0)
        XCTAssertEqual(history.foregroundDuration(during: (date - 100)...(date + 5)), 5)
        XCTAssertEqual(history.foregroundDuration(during: (date - 100)...(date + 10)), 5)
        XCTAssertEqual(history.foregroundDuration(during: (date)...(date + 100)), 95, "It should extrapolate last state to upper range")
        XCTAssertEqual(history.foregroundDuration(during: (date + 10)...(date + 100)), 90)
    }

    // MARK: - `containsState(during:where:)`

    func testContainsState_whenOnlyInitialState() {
        // Given
        let history = AppStateHistory(initialState: .active, date: date)

        // When / Then
        XCTAssertTrue(history.containsState(during: date...(date + 10), where: { $0 == .active }))
        XCTAssertFalse(history.containsState(during: date...(date + 10), where: { $0 == .background }))
    }

    func testStates_whenMultipleTransitions() {
        // Given
        var history = AppStateHistory(initialState: .active, date: date)

        // When
        history.append(state: .inactive, at: date + 1)
        history.append(state: .background, at: date + 2)
        history.append(state: .active, at: date + 3)

        // Then
        XCTAssertTrue(history.containsState(during: date...(date + 10), where: { $0 == .active }))
        XCTAssertTrue(history.containsState(during: date...(date + 10), where: { $0 == .inactive }))
        XCTAssertTrue(history.containsState(during: date...(date + 10), where: { $0 == .background }))

        XCTAssertFalse(history.containsState(during: (date + 3.1)...(date + 10), where: { $0 == .background }))
        XCTAssertFalse(history.containsState(during: (date + 2.1)...(date + 3), where: { $0 == .inactive }))
    }

    func testContainsState_whenOutsideRange() {
        // Given
        var history = AppStateHistory(initialState: .active, date: date)

        // When
        history.append(state: .inactive, at: date + 5)
        history.append(state: .background, at: date + 10)

        // Then
        XCTAssertFalse(history.containsState(during: (date - 100)...(date - 50), where: { _ in true }))
        XCTAssertTrue(history.containsState(during: (date + 20)...(date + 50), where: { $0 == .background }))
        XCTAssertTrue(history.containsState(during: (date - 50)...(date + 1), where: { $0 == .active }))
    }
}
