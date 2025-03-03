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
    func testWhenReceivingAppLifecycleNotification_itUpdatesStatesHistory() throws {
        let date = Date()
        let dateProvider = DateProviderMock(now: date)
        let notificationCenter = NotificationCenter()

        // Given
        let publisher = ApplicationStatePublisher(
            appStateHistory: .mockWith(initialState: .inactive, date: dateProvider.now),
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )

        var lastPublishedValue: AppStateHistory?
        publisher.publish { lastPublishedValue = $0 }

        // When / Then
        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .inactive)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .active)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .inactive)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .background)

        let history = try XCTUnwrap(lastPublishedValue)
        XCTAssertEqual(history.state(at: date), .inactive)
        XCTAssertEqual(history.state(at: date + 1), .inactive)
        XCTAssertEqual(history.state(at: date + 2), .active)
        XCTAssertEqual(history.state(at: date + 3), .inactive)
        XCTAssertEqual(history.state(at: date + 4), .background)

        XCTAssertNil(history.state(at: date - 1))
        XCTAssertEqual(history.initialState, .inactive)
        XCTAssertEqual(history.state(at: .distantFuture), .background)
    }
}
