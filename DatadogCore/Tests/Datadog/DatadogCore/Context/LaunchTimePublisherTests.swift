/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class LaunchTimePublisherTests: XCTestCase {
    func testInitialValueWhenTimeToDidBecomeActiveIsYetNotAvailable() {
        let launchDate: Date = .mockRandom()
        let isActivePrewarm: Bool = .mockRandom()

        // Given
        let handler = AppLaunchHandlerMock(
            launchDate: launchDate,
            timeToDidBecomeActive: nil, // not yet available
            isActivePrewarm: isActivePrewarm
        )

        // When
        let publisher = LaunchTimePublisher(handler: handler)

        // Then
        XCTAssertEqual(publisher.initialValue.launchDate, launchDate)
        XCTAssertEqual(publisher.initialValue.isActivePrewarm, isActivePrewarm)
        XCTAssertNil(publisher.initialValue.launchTime)
    }

    func testInitialValueWhenTimeToDidBecomeActiveIsAlreadyAvailable() {
        let launchDate: Date = .mockRandom()
        let isActivePrewarm: Bool = .mockRandom()
        let timeToDidBecomeActive: TimeInterval = .mockRandom(min: 1, max: 10)

        // Given
        let handler = AppLaunchHandlerMock(
            launchDate: launchDate,
            timeToDidBecomeActive: timeToDidBecomeActive,
            isActivePrewarm: isActivePrewarm
        )

        // When
        let publisher = LaunchTimePublisher(handler: handler)

        // Then
        XCTAssertEqual(publisher.initialValue.launchDate, launchDate)
        XCTAssertEqual(publisher.initialValue.isActivePrewarm, isActivePrewarm)
        XCTAssertEqual(publisher.initialValue.launchTime, timeToDidBecomeActive)
    }

    func testUpdatingValue() {
        let launchDate: Date = .mockRandom()
        let isActivePrewarm: Bool = .mockRandom()
        let timeToDidBecomeActive: TimeInterval = .mockRandom(min: 1, max: 10)

        // Given
        let handler = AppLaunchHandlerMock(
            launchDate: launchDate,
            timeToDidBecomeActive: nil, // it will be lazy updated
            isActivePrewarm: isActivePrewarm
        )
        let contextUpdated = expectation(description: "Update context receiver")
        let publisher = LaunchTimePublisher(handler: handler)

        publisher.publish { launchTime in
            XCTAssertEqual(launchTime.launchDate, launchDate)
            XCTAssertEqual(launchTime.isActivePrewarm, isActivePrewarm)
            XCTAssertEqual(launchTime.launchTime, timeToDidBecomeActive)
            contextUpdated.fulfill()
        }

        // When
        handler.simulateDidBecomeActive(timeInterval: timeToDidBecomeActive)

        // Then
        waitForExpectations(timeout: 1)
    }
}

class AppLaunchHandlerTests: XCTestCase {
    let notificationCenter = NotificationCenter()
    let processInfo = ProcessInfoMock()

    func testActivePrewarm() {
        // When
        let handler1 = AppLaunchHandler.create(
            with: ProcessInfoMock(environment: ["ActivePrewarm": "1"]),
            notificationCenter: notificationCenter
        )
        let handler2 = AppLaunchHandler.create(
            with: ProcessInfoMock(environment: [:]),
            notificationCenter: notificationCenter
        )

        // Then
        XCTAssertTrue(handler1.currentValue.isActivePrewarm)
        XCTAssertFalse(handler2.currentValue.isActivePrewarm)
    }

    func testLaunchTime() {
        // Given
        let handler = AppLaunchHandler.create(with: processInfo, notificationCenter: notificationCenter)
        XCTAssertNil(handler.launchTime)

        // When
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        XCTAssertNotNil(handler.launchTime)
    }

    func testSetApplicationDidBecomeActiveCallback() {
        // Given
        let handler = AppLaunchHandler.create(with: processInfo, notificationCenter: notificationCenter)
        let callbackNotified = expectation(description: "Notify setApplicationDidBecomeActiveCallback()")
        handler.setApplicationDidBecomeActiveCallback { _ in callbackNotified.fulfill() }

        // When
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        waitForExpectations(timeout: 1)
    }

    func testThreadSafety() {
        let handler = AppLaunchHandler.create(with: processInfo, notificationCenter: notificationCenter)

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = handler.launchTime },
                { _ = handler.launchDate },
                { _ = handler.isActivePrewarm },
                { handler.setApplicationDidBecomeActiveCallback { _ in } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }
}
