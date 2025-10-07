/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class LaunchInfoPublisherTests: XCTestCase {
    func testInitialValue() {
        // Given
        let handler = AppLaunchHandlerMock(didBecomeActiveDate: nil)
        let initialValue: LaunchInfo = .mockRandom()

        // When
        let publisher = LaunchInfoPublisher(handler: handler, initialValue: initialValue)

        // Then
        XCTAssertEqual(publisher.initialValue, initialValue)
    }

    func testUpdatingValue() {
        let taskPolicyRole = Int(TASK_FOREGROUND_APPLICATION.rawValue)
        let processLaunchDate: Date = .mockRandom()
        let didBecomeActiveDate: Date = processLaunchDate.addingTimeInterval(TimeInterval.mockRandom(min: 1, max: 10))

        // Given
        let handler = AppLaunchHandlerMock(
            taskPolicyRole: taskPolicyRole,
            processLaunchDate: processLaunchDate,
            didBecomeActiveDate: nil // it will be lazy updated
        )
        let initialValue = handler.resolveLaunchInfo(using: ProcessInfoMock())
        let contextUpdated = expectation(description: "Update context receiver")
        let publisher = LaunchInfoPublisher(handler: handler, initialValue: initialValue)

        publisher.publish { launchInfo in
            XCTAssertEqual(launchInfo.launchReason, .userLaunch)
            XCTAssertEqual(launchInfo.processLaunchDate, processLaunchDate)
            XCTAssertEqual(launchInfo.launchPhaseDates[.didBecomeActive], didBecomeActiveDate)
            contextUpdated.fulfill()
        }

        // When
        handler.simulateDidBecomeActive(date: didBecomeActiveDate)

        // Then
        waitForExpectations(timeout: 1)
    }
}

class AppLaunchHandlerLaunchInfoTests: XCTestCase {
    /// The heuristic tested here is explained in https://datadoghq.atlassian.net/wiki/x/eQHZMAE
    func testResolvingLaunchReason() {
        // ProcessInfo env specific to "prewarmed" launch reason:
        let prewarmedProcessInfo = ["ActivePrewarm": "1"]
        // Task role specific to "user launch" reason:
        let foregroundRole = Int(TASK_FOREGROUND_APPLICATION.rawValue)
        // Task role specific to "uncertain" launch reason on tvOS:
        let unavailableRole = __dd_private_TASK_POLICY_UNAVAILABLE
        // Other known task roles:
        let otherRoles: [Int] = [
            Int(TASK_UNSPECIFIED.rawValue),
            Int(TASK_BACKGROUND_APPLICATION.rawValue),
            Int(TASK_CONTROL_APPLICATION.rawValue),
            Int(TASK_GRAPHICS_SERVER.rawValue),
            Int(TASK_THROTTLE_APPLICATION.rawValue),
            Int(TASK_NONUI_APPLICATION.rawValue),
            Int(TASK_DEFAULT_APPLICATION.rawValue),
            Int(TASK_DARWINBG_APPLICATION.rawValue),
            __dd_private_TASK_POLICY_KERN_FAILURE,
            __dd_private_TASK_POLICY_DEFAULTED,
        ]

        func launchReason(for taskPolicyRole: Int, processInfo: [String: String]) -> LaunchReason {
            let handler = AppLaunchHandlerMock(taskPolicyRole: taskPolicyRole)
            let info = handler.resolveLaunchInfo(using: ProcessInfoMock(environment: processInfo))
            return info.launchReason
        }

        // Unavailable role is always uncertain, regardless of ActivePrewarm:
        XCTAssertEqual(launchReason(for: unavailableRole, processInfo: [:]), .uncertain)
        XCTAssertEqual(launchReason(for: unavailableRole, processInfo: prewarmedProcessInfo), .uncertain)

        // Foreground policy and no prewarm → user launch:
        XCTAssertEqual(launchReason(for: foregroundRole, processInfo: [:]), .userLaunch)
        // Foreground policy but ActivePrewarm=1 → prewarming overrides user:
        XCTAssertEqual(launchReason(for: foregroundRole, processInfo: prewarmedProcessInfo), .prewarming)

        for otherRole in otherRoles {
            // Other roles + no prewarm → background:
            XCTAssertEqual(launchReason(for: otherRole, processInfo: [:]), .backgroundLaunch)
            // Other roles + prewarm → prewarming:
            XCTAssertEqual(launchReason(for: otherRole, processInfo: prewarmedProcessInfo), .prewarming)
        }
    }

    func testProcessLaunchDateForwarding() {
        let expectedDate = Date()
        let handler = AppLaunchHandlerMock(processLaunchDate: expectedDate)
        let info = handler.resolveLaunchInfo(using: ProcessInfoMock())
        XCTAssertEqual(info.processLaunchDate, expectedDate)
    }

    func testTimeToDidBecomeActiveForwarding() {
        let processLaunchDate = Date()
        let expectedInterval: TimeInterval = 4.56
        let didBecomeActiveDate = processLaunchDate.addingTimeInterval(expectedInterval)
        let handler = AppLaunchHandlerMock(processLaunchDate: processLaunchDate, didBecomeActiveDate: didBecomeActiveDate)
        let info = handler.resolveLaunchInfo(using: ProcessInfoMock())
        XCTAssertEqual(info.launchPhaseDates[.didBecomeActive], didBecomeActiveDate)
    }

    func testTimeToDidBecomeActiveForwardingNil() {
        let handler = AppLaunchHandlerMock(didBecomeActiveDate: nil)
        let info = handler.resolveLaunchInfo(using: ProcessInfoMock())
        XCTAssertNil(info.launchPhaseDates[.didBecomeActive])
    }
}

class AppLaunchHandlerTests: XCTestCase {
    let notificationCenter = NotificationCenter()

    func testTaskPolicyRole() {
        let handler = AppLaunchHandler()
        #if os(tvOS)
        XCTAssertEqual(handler.taskPolicyRole, __dd_private_TASK_POLICY_UNAVAILABLE)
        #else
        XCTAssertEqual(handler.taskPolicyRole, Int(TASK_FOREGROUND_APPLICATION.rawValue))
        #endif
    }

    func testProcessLaunchDate() {
        // Given
        let handler = AppLaunchHandler()

        // When
        let processLaunchDate = handler.processLaunchDate
        let now = Date()
        let uptime = now.timeIntervalSince(processLaunchDate)

        // Then
        // Sanity check: process launch date should be in the past, and not unreasonably far back.
        XCTAssertGreaterThan(uptime, 0, "Process launch date should be in the past.")
        XCTAssertLessThan(uptime, 3_600, "Process uptime should be less than 1 hour — test process likely launched recently.")
    }

    func testTimeToDidBecomeActive() {
        // Given
        let handler = AppLaunchHandler()
        XCTAssertNil(handler.didBecomeActiveDate)

        // When
        handler.observe(notificationCenter)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        XCTAssertNotNil(handler.didBecomeActiveDate)
    }

    func testTimeToDidFinishLaunching() {
        // Given
        let handler = AppLaunchHandler()
        XCTAssertNil(handler.didFinishLaunchingDate)

        // When
        handler.observe(notificationCenter)
        notificationCenter.post(name: ApplicationNotifications.didFinishLaunching, object: nil)

        // Then
        XCTAssertNotNil(handler.didFinishLaunchingDate)
    }

    func testSetApplicationNotificationCallback() {
        // Given
        let handler = AppLaunchHandler()
        let callbackNotified = expectation(description: "Notify setApplicationNotificationCallback()")
        handler.setApplicationNotificationCallback { _, _ in callbackNotified.fulfill() }

        // When
        handler.observe(notificationCenter)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        waitForExpectations(timeout: 1)
    }

    func testSetApplicationNotificationCallbackByMultipleHandlers() {
        // Given
        let handlersCount = 3
        let handlers = (0..<handlersCount).map { _ in AppLaunchHandler() }
        let notified = expectation(description: "All handlers notified")
        notified.expectedFulfillmentCount = handlersCount

        handlers.forEach { handler in
            handler.setApplicationNotificationCallback { _, _ in
                notified.fulfill()
            }
            handler.observe(notificationCenter)
        }

        // When
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        waitForExpectations(timeout: 1)
    }

    func testApplicationNotificationCallbackIsOnlyCalledOnce() {
        // Given
        let handler = AppLaunchHandler()
        let callbackNotified = expectation(description: "Notify setApplicationNotificationCallback()")
        handler.setApplicationNotificationCallback { _, _ in callbackNotified.fulfill() }

        // When
        handler.observe(notificationCenter)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        waitForExpectations(timeout: 1)
    }

    func testSetApplicationDidBecomeActiveCallbackByMultipleEntities() {
        // Given
        let handler = AppLaunchHandler()
        let callbacksCount = 10
        let notified = expectation(description: "All callbacks notified")
        notified.expectedFulfillmentCount = callbacksCount

        (0..<callbacksCount).forEach { _ in
            handler.setApplicationDidBecomeActiveCallback { _ in notified.fulfill() }
        }

        // When
        handler.observe(notificationCenter)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        waitForExpectations(timeout: 1)
    }

    func testApplicationDidBecomeActiveMultipleTimesInMultipleEntities() {
        // Given
        let handler = AppLaunchHandler()
        let callbacksCount: Int = .mockRandom(min: 3, max: 10)
        let notificationsCount: Int = .mockRandom(min: 3, max: 10)
        let notified = expectation(description: "All callbacks notified")
        notified.expectedFulfillmentCount = callbacksCount

        (0..<callbacksCount).forEach { _ in
            handler.setApplicationDidBecomeActiveCallback { _ in notified.fulfill() }
        }

        // When
        handler.observe(notificationCenter)
        (0..<notificationsCount).forEach { _ in
            notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        }

        // Then
        waitForExpectations(timeout: 1)
    }

    func testThreadSafety() {
        let handler = AppLaunchHandler()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = handler.taskPolicyRole },
                { _ = handler.processLaunchDate },
                { _ = handler.didBecomeActiveDate },
                { handler.setApplicationNotificationCallback { _, _ in } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }
}
