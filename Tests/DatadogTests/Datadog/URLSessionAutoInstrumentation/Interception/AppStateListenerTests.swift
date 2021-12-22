/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class AppStateHistoryTests: XCTestCase {
    func testItBuildsAppStateFromUIApplicationState() {
        XCTAssertEqual(AppState(uiApplicationState: .active), .active)
        XCTAssertEqual(AppState(uiApplicationState: .inactive), .inactive)
        XCTAssertEqual(AppState(uiApplicationState: .background), .background)
    }

    func testWhenAppTransitionsBetweenForegroundAndBackground_itComputesTotalForegroundDuration() {
        let numberOfForegroundSnapshots: Int = .mockRandom(min: 0, max: 20)
        let numberOfBackgroundSnapshots: Int = .mockRandom(min: numberOfForegroundSnapshots == 0 ? 1 : 0, max: 20) // must include at least one snapshot
        let numberOfSnapshots = numberOfForegroundSnapshots + numberOfBackgroundSnapshots
        let snapshotDuration: TimeInterval = .mockRandom(min: 0.1, max: 5)

        // Given
        let date: Date = .mockRandomInThePast()
        let snapshotDates: [Date] = (0..<numberOfSnapshots).shuffled()
            .map { idx in date.addingTimeInterval(TimeInterval(idx) * snapshotDuration) }
        let foregroundSnapshots = snapshotDates.dropLast(numberOfBackgroundSnapshots)
            .map { AppStateHistory.Snapshot(state: .mockRandom(runningInForeground: true), date: $0) }
        let backgroundSnapshots = snapshotDates.dropFirst(numberOfForegroundSnapshots)
            .map { AppStateHistory.Snapshot(state: .mockRandom(runningInForeground: false), date: $0) }

        // When
        let allSnapshots = (foregroundSnapshots + backgroundSnapshots).sorted { $0.date < $1.date }
        let totalDuration = TimeInterval(numberOfSnapshots) * snapshotDuration

        let history = AppStateHistory(
            initialSnapshot: allSnapshots[0],
            snapshots: Array(allSnapshots.dropFirst()),
            recentDate: date.addingTimeInterval(totalDuration)
        )

        // Then
        let expectedForegroundDuration = TimeInterval(numberOfForegroundSnapshots) * snapshotDuration
        XCTAssertEqual(history.foregroundDuration, expectedForegroundDuration, accuracy: 0.01)
    }

    func testExtrapolation() {
        let randomAppState: AppState = .mockRandom()
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate),
            snapshots: [],
            recentDate: startDate + 5.0
        )
        let extrapolatedHistory = history.take(
            between: (startDate - 5.0)...(startDate + 15.0)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate - 5.0),
            snapshots: [],
            recentDate: startDate + 15.0
        )
        XCTAssertEqual(extrapolatedHistory, expectedHistory)
    }

    func testLimiting() {
        let randomAppState: AppState = .mockRandom()
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate),
            snapshots: [],
            recentDate: startDate + 20.0
        )
        let limitedHistory = history.take(
            between: (startDate + 5.0)...(startDate + 10.0)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate + 5.0),
            snapshots: [],
            recentDate: startDate + 10.0
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }

    func testLimitingWithChanges() {
        let randomFirstAppState: AppState = .mockRandom()
        let randomLastAppState: AppState = .mockRandom()

        let startDate = Date(timeIntervalSinceReferenceDate: 0.0)
        let firstChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                state: randomFirstAppState,
                date: startDate + TimeInterval.random(in: 1...1_000)
            )
        }
        let lastChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                state: randomLastAppState,
                date: startDate + TimeInterval.random(in: 2_000...3_000)
            )
        }
        var allChanges = (firstChanges + lastChanges)
        allChanges.append(.init(state: randomFirstAppState, date: startDate + 1_200))
        allChanges.append(.init(state: randomLastAppState, date: startDate + 1_500))
        allChanges.sort { $0.date < $1.date }
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomFirstAppState, date: startDate),
            snapshots: allChanges,
            recentDate: startDate + 4_000
        )

        let limitedHistory = history.take(
            between: (startDate + 1_250)...(startDate + 1_750)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomFirstAppState, date: startDate + 1_250),
            snapshots: [.init(state: randomLastAppState, date: startDate + 1_500)],
            recentDate: startDate + 1_750
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }
}

class AppStateListenerTests: XCTestCase {
    private let dateProvider = SystemDateProvider()
    private let notificationCenter = NotificationCenter()
    private let supportedNotifications = [
        (name: UIApplication.didBecomeActiveNotification, expectedState: AppState.active),
        (name: UIApplication.willResignActiveNotification, expectedState: AppState.inactive),
        (name: UIApplication.didEnterBackgroundNotification, expectedState: AppState.background),
        (name: UIApplication.willEnterForegroundNotification, expectedState: AppState.inactive),
    ]

    // MARK: - Handling UIApplication Notifications

    func testWhenReceivingAppLifecycleNotification_itRecordsItsState() {
        // Given
        let listener = AppStateListener(
            dateProvider: dateProvider,
            initialAppState: .mockRandom(),
            notificationCenter: notificationCenter
        )

        // When
        let randomNotification = supportedNotifications.randomElement()!
        notificationCenter.post(name: randomNotification.name, object: nil)

        // Then
        XCTAssertEqual(
            listener.history.currentSnapshot.state,
            randomNotification.expectedState,
            "It must record \(randomNotification.expectedState) after receiving '\(randomNotification.name)'"
        )
    }

    // MARK: - Recording History

    func testWhenAppStatesHistoryIsRetrieved_thenCurrentSnapshotIsSignedWithRecentDate() {
        let listener = AppStateListener(
            dateProvider: RelativeDateProvider(startingFrom: .mockRandomInThePast(), advancingBySeconds: 1.0),
            initialAppState: .mockRandom(),
            notificationCenter: notificationCenter
        )
        let history1 = listener.history
        let history2 = listener.history

        XCTAssertEqual(history2.currentSnapshot.date.timeIntervalSince(history1.currentSnapshot.date), 1.0)
    }

    func testWhenReceivingStateChangeNotifications_itRecordsHistoryOfAppStates() {
        var expectedHistoryStates: [AppState] = []

        // Given
        let listener = AppStateListener(
            dateProvider: RelativeDateProvider(startingFrom: .mockRandomInThePast(), advancingBySeconds: 1.0),
            initialAppState: .mockRandom(),
            notificationCenter: notificationCenter
        )

        // When
        (0..<10).forEach { _ in
            let randomNotification = supportedNotifications.randomElement()!
            notificationCenter.post(name: randomNotification.name, object: nil)
            expectedHistoryStates.append(randomNotification.expectedState)
        }

        // Then
        XCTAssertEqual(listener.history.snapshots.map({ $0.state }), expectedHistoryStates, "It must record all app state changes")
    }

    // MARK: - Thread Safety

    func testWhenAppStateListenerIsCalledFromDifferentThreads_thenItWorks() {
        let listener = AppStateListener(
            dateProvider: SystemDateProvider(),
            initialAppState: .mockAny(),
            notificationCenter: notificationCenter
        )
        let notificationNames = supportedNotifications.map { $0.name }

        DispatchQueue.concurrentPerform(iterations: 10_000) { iteration in
            // write
            if iteration < 1_000 {
                notificationCenter.post(name: notificationNames.randomElement()!, object: nil)
            }
            // read
            XCTAssertFalse(listener.history.snapshots.isEmpty)
        }
    }
}
