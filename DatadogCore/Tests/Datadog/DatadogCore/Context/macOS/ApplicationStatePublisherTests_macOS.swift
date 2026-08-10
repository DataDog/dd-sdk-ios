/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)
import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

@MainActor
class ApplicationStatePublisherTests: XCTestCase {
    private class TestApplicationStateProvider: MacOSApplicationStateProvider {
        var isActive: Bool = true
        var isHidden: Bool = false
        var frontmostApplicationIsLoginWindow: Bool = false
    }

    private class TestRunningApplication: NSRunningApplication, @unchecked Sendable {
        override var bundleIdentifier: String? {
            "com.apple.loginwindow"
        }
    }

    @available(macOS 14.0, *)
    func testWhenReceivingAppLifecycleNotification_itUpdatesStatesHistory() throws {
        let date = Date()
        let dateProvider = DateProviderMock(now: date)
        let appNotificationCenter = NotificationCenter()
        let wsNotificationCenter = NotificationCenter()
        let applicationStateProvider = TestApplicationStateProvider()

        // Given
        let publisher = ApplicationStatePublisher(
            appStateHistory: .mockWith(initialState: .active, date: dateProvider.now),
            applicationNotificationCenter: appNotificationCenter,
            workspaceNotificationCenter: wsNotificationCenter,
            applicationStateProvider: applicationStateProvider,
            dateProvider: dateProvider
        )

        var lastPublishedValue: AppStateHistory?
        publisher.publish { lastPublishedValue = $0 }

        // When / Then
        dateProvider.now += 1
        applicationStateProvider.isActive = false
        appNotificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .inactive)

        dateProvider.now += 1
        applicationStateProvider.isActive = true
        appNotificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .active)

        dateProvider.now += 1
        applicationStateProvider.isHidden = true
        appNotificationCenter.post(name: ApplicationNotifications.didHide, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .hidden)

        dateProvider.now += 1
        applicationStateProvider.isHidden = false
        appNotificationCenter.post(name: ApplicationNotifications.didUnhide, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .active)

        dateProvider.now += 1
        wsNotificationCenter.post(name: WorkspaceNotifications.didActivateApplication, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: TestRunningApplication()])
        XCTAssertEqual(lastPublishedValue?.currentState, .lockScreen)

        dateProvider.now += 1
        wsNotificationCenter.post(name: WorkspaceNotifications.didDeactivateApplication, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: TestRunningApplication()])
        XCTAssertEqual(lastPublishedValue?.currentState, .active)

        dateProvider.now += 1
        wsNotificationCenter.post(name: WorkspaceNotifications.willSleep, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .sleeping)

        dateProvider.now += 1
        wsNotificationCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .active)

        dateProvider.now += 1
        appNotificationCenter.post(name: ApplicationNotifications.willTerminate, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .terminating)

        dateProvider.now += 1
        applicationStateProvider.isActive = false
        appNotificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .terminating)

        dateProvider.now += 1
        applicationStateProvider.isActive = true
        appNotificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)
        XCTAssertEqual(lastPublishedValue?.currentState, .terminating)

        let history = try XCTUnwrap(lastPublishedValue)
        let expectedValues = [
            AppState.active,
            .inactive,
            .active,
            .hidden,
            .active,
            .lockScreen,
            .active,
            .sleeping,
            .active,
            .terminating,
            .terminating,
            .terminating
        ]
        var step = TimeInterval(0)
        expectedValues.forEach { expectedState in
            XCTAssertEqual(
                history.state(at: date + step),
                expectedState,
                "Expected \(expectedState), got \(String(describing: history.state(at: date + step))) at step \(String(format: "%0.0f", step))"
            )

            step += 1
        }

        XCTAssertNil(history.state(at: date - 1))
        XCTAssertEqual(history.initialState, .active)
        XCTAssertEqual(history.state(at: .distantFuture), .terminating)
    }
}
#endif
