/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

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
