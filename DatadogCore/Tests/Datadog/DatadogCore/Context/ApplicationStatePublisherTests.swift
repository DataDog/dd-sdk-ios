/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class ApplicationStateSourceTests: XCTestCase {
    func testWhenReceivingAppLifecycleNotification_itUpdatesStatesHistory() async throws {
        let date = Date()
        let dateProvider = DateProviderMock(now: date)
        let notificationCenter = NotificationCenter()

        // Given
        let source = ApplicationStateSource(
            appStateHistory: .mockWith(initialState: .inactive, date: dateProvider.now),
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )

        var iterator = source.values.makeAsyncIterator()

        // When / Then
        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        var value = await iterator.next()
        XCTAssertEqual(value?.currentState, .inactive)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        value = await iterator.next()
        XCTAssertEqual(value?.currentState, .active)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        value = await iterator.next()
        XCTAssertEqual(value?.currentState, .inactive)

        dateProvider.now += 1
        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        value = await iterator.next()
        XCTAssertEqual(value?.currentState, .background)

        let history = try XCTUnwrap(value)
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
