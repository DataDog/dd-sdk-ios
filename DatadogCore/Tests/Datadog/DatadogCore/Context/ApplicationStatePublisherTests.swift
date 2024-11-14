/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class ApplicationStatePublisherTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    private let supportedNotifications = [
        (name: UIApplication.didBecomeActiveNotification, expectedState: AppState.active),
        (name: UIApplication.willResignActiveNotification, expectedState: AppState.inactive),
        (name: UIApplication.didEnterBackgroundNotification, expectedState: AppState.background),
        (name: UIApplication.willEnterForegroundNotification, expectedState: AppState.inactive),
    ]

    // MARK: - Handling UIApplication Notifications

    func testWhenReceivingAppLifecycleNotification_itRecordsItsState() {
        let expectation = expectation(description: "app state publisher publishes value")

        // Given
        let publisher = ApplicationStatePublisher(
            appStateProvider: AppStateProviderMock(state: .mockRandom()),
            notificationCenter: notificationCenter,
            dateProvider: SystemDateProvider()
        )

        // When
        let notification = supportedNotifications.randomElement()!

        publisher.publish { state in
            // Then
            XCTAssertEqual(
                state.currentSnapshot.state,
                notification.expectedState,
                "It must record \(notification.expectedState) after receiving '\(notification.name)'"
            )
            expectation.fulfill()
        }

        notificationCenter.post(name: notification.name, object: nil)

        waitForExpectations(timeout: 1)
    }

    // MARK: - Recording History

    func testWhenReceivingStateChangeNotifications_itRecordsHistoryOfAppStates() {
        let expectation = expectation(description: "app state publisher publishes values")
        expectation.expectedFulfillmentCount = 100

        // Given
        let publisher = ApplicationStatePublisher(
            appStateProvider: AppStateProviderMock(state: .mockRandom()),
            notificationCenter: notificationCenter,
            dateProvider: RelativeDateProvider(startingFrom: .mockRandomInThePast(), advancingBySeconds: 1.0)
        )

        var receivedHistoryStates: [AppState?] = []
        let expectedNotifications = (0..<expectation.expectedFulfillmentCount).map { _ in
            supportedNotifications.randomElement()!
        }

        // When
        publisher.publish { state in
            receivedHistoryStates.append(state.currentSnapshot.state)
            expectation.fulfill()
        }

        DispatchQueue.concurrentPerform(iterations: expectation.expectedFulfillmentCount) { iteration in
            notificationCenter.post(name: expectedNotifications[iteration].name, object: nil)
        }

        waitForExpectations(timeout: 5)

        // Then
        let expectedHistoryStates = expectedNotifications.map { $0.expectedState }
        XCTAssertEqual(receivedHistoryStates.count, expectedHistoryStates.count)
        XCTAssertEqual(Set(receivedHistoryStates), Set(expectedHistoryStates), "It must record all app state changes")
    }
}
