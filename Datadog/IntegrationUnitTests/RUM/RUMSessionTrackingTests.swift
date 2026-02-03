/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

class RUMSessionTrackingTests: RUMSessionTestsBase {
    private func enableRUM(_ launchType: AppRunner.ProcessLaunchType, rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: launchType))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    private let dt: TimeInterval = 1

    // MARK: - User Launch → track user session

    /// User launch in `UISceneDelegate`-based app.
    private var userLaunchWithSceneDelegate: AppRunner.ProcessLaunchType { .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate) }
    /// User launch in `UIApplicationDelegate`-based app.
    private var userLaunchWithAppDelegate: AppRunner.ProcessLaunchType { .userLaunchInAppDelegateBasedApp(processLaunchDate: processLaunchDate) }

    private func simulateUserSession(in run: AppRun) -> AppRun {
        // Track app launch events within "ApplicationLaunch" view:
        var run = run
            .when(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Move to foreground, start "FirstView" and track events:
        run = run
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.appDisplaysFirstFrame())
            .and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "FirstView")))
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Switch to "SecondView" and track events::
        run = run
            .and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "SecondView")))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.startResource(after: dt, key: "foreground-resource", url: .mockAny()))

        // Move to background, and track events:
        run = run
            .and(.appEntersBackground(after: dt))
            .and(.stopResource(after: dt, key: "foreground-resource"))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))
            .and(.startResource(after: dt, key: "background-resource", url: .mockAny()))

        // Move to back foreground ("SecondView"), and track events:
        run = run
            .and(.appBecomesActive(after: dt))
            .and(.stopResource(after: dt, key: "background-resource"))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))

        return run
    }

    private func assertUserSession(
        session: RUMSessionMatcher,
        expectBackgroundView: Bool
    ) {
        XCTAssertNotNil(session.ttidEvent)
        DDAssertEqual(session.timeToInitialDisplay, timeToSDKInit + 4 + timeToAppBecomeActive, accuracy: accuracy)
        DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
        DDAssertEqual(session.duration, timeToSDKInit + 4 * dt + timeToAppBecomeActive + 18 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)

        var views = session.views
        var nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, applicationLaunchViewName)
        DDAssertEqual(nextView.duration, timeToSDKInit + 4 * dt + timeToAppBecomeActive, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 0)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "FirstView")
        DDAssertEqual(nextView.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 0)
        XCTAssertEqual(nextView.resourceEvents.count, 1)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "SecondView")
        DDAssertEqual(nextView.duration, 5 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 1)
        XCTAssertEqual(nextView.longTaskEvents.count, 0)

        if expectBackgroundView {
            nextView = views.removeFirst()
            XCTAssertEqual(nextView.name, backgroundViewName)
            DDAssertEqual(nextView.duration, 2 * dt, accuracy: accuracy)
            XCTAssertEqual(nextView.actionEvents.count, 0)
            XCTAssertEqual(nextView.resourceEvents.count, 1)
            XCTAssertEqual(nextView.longTaskEvents.count, 0)
        }

        nextView = views.removeFirst()
        XCTAssertEqual(nextView.name, "SecondView")
        DDAssertEqual(nextView.duration, 5 * dt, accuracy: accuracy)
        XCTAssertEqual(nextView.actionEvents.count, 2)
        XCTAssertEqual(nextView.resourceEvents.count, 0)
        XCTAssertEqual(nextView.longTaskEvents.count, 2)

        XCTAssertTrue(views.isEmpty)
    }

    func testGivenUserLaunch_whenTrackingUserSession() throws {
        // Given
        // - BET disabled
        let givens = [
            enableRUM(userLaunchWithSceneDelegate) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() },
            enableRUM(userLaunchWithAppDelegate) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() },
            enableRUM(userLaunchWithSceneDelegate) {
                $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                $0.trackBackgroundEvents = true
            },
            enableRUM(userLaunchWithAppDelegate) {
                $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                $0.trackBackgroundEvents = true
            },
        ]

        for given in givens {
            // When
            let when = simulateUserSession(in: given)

            // Then
            let session = try when.then().takeSingle()
            assertUserSession(
                session: session,
                expectBackgroundView: given == givens[2] || given == givens[3]
            )
        }
    }

    // MARK: - Prewarming & Background Launch → track background session

    private func simulateBackgroundSession(in run: AppRun) -> AppRun {
        // Track background events:
        var run = run
            .when(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        // Await tvOS launch window duration:
        run = run
            .and(.init { $0.advanceTime(by: LaunchReasonResolver.Constants.launchWindowThreshold) })

        // Track more background events:
        run = run
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        return run
    }

    private func assertBackgroundSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt, accuracy: accuracy)
        DDAssertEqual(session.duration, 5 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 6 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, backgroundViewName)
        DDAssertEqual(view.duration, 5 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 6 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 4)
        XCTAssertEqual(view.resourceEvents.count, 2)
        XCTAssertEqual(view.longTaskEvents.count, 4)
    }

    @available(tvOS, unavailable)
    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate, runtimeLoadDate: runtimeLoadDate) }

    @available(tvOS, unavailable)
    func testGivenPrewarmedLaunch_whenTrackingBackgroundSession() throws {
        // Given
        // - BET disabled
        let given = enableRUM(osPrewarmLaunch)

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let sessions = try when.then()
        XCTAssertTrue(sessions.isEmpty)
    }

    @available(tvOS, unavailable)
    func testGivenPrewarmedLaunch_andBETEnabled_whenTrackingBackgroundSession() throws {
        // Given
        // - BET enabled
        let given = enableRUM(osPrewarmLaunch) { $0.trackBackgroundEvents = true }

        let when = simulateBackgroundSession(in: given)

        let session = try when.then().takeSingle()
        assertBackgroundSession(session: session, expectedSessionPrecondition: .prewarm)
    }

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenTrackingBackgroundSession() throws {
        // Given
        // - BET disabled
        let given = enableRUM(backgroundLaunch)

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let sessions = try when.then()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testGivenBackgroundLaunch_andBETEnabled_whenTrackingBackgroundSession() throws {
        // Given
        // - BET enabled
        let given = enableRUM(backgroundLaunch) { $0.trackBackgroundEvents = true }

        // When
        let when = simulateBackgroundSession(in: given)

        // Then
        let session = try when.then().takeSingle()
        assertBackgroundSession(session: session, expectedSessionPrecondition: .backgroundLaunch)
    }

    // MARK: - Prewarming & Background Launch → suspend → resume by user session

    private func simulateSuspendedBackgroundSessionResumedByUser(in run: AppRun) -> AppRun {
        // Track background events:
        var run = run
            .when(.trackResource(after: dt, duration: dt))
            .and(.trackTwoActions(after1: dt, after2: dt))
            .and(.init { $0.advanceTime(by: LaunchReasonResolver.Constants.launchWindowThreshold) })
            .and(.trackResource(after: dt, duration: dt))

        // Suspend for long time
        run = run
            .and(.advanceTime(by: 2.hours))

        // Move to foreground, start "FirstView" and track events:
        run = run
            .and(.appBecomesActive(after: 0))
            .and(.startAutomaticView(after: 0, viewController: createMockView(viewControllerClassName: "FirstView")))
            .and(.trackResource(after: dt, duration: dt))
            .and(.trackTwoLongTasks(after1: dt, after2: dt))

        return run
    }

    private func assertSuspendedBackgroundSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt, accuracy: accuracy)
        DDAssertEqual(session.duration, 3 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, backgroundViewName)
        DDAssertEqual(view.duration, 3 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 2)
        XCTAssertEqual(view.resourceEvents.count, 2)
        XCTAssertEqual(view.longTaskEvents.count, 0)
    }

    private func assertResumedUserSession(
        session: RUMSessionMatcher,
        expectedSessionPrecondition: RUMSessionPrecondition
    ) {
        XCTAssertNil(session.ttidEvent)
        XCTAssertNil(session.timeToInitialDisplay)
        DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + 6 * dt + LaunchReasonResolver.Constants.launchWindowThreshold + 2.hours, accuracy: accuracy)
        DDAssertEqual(session.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, expectedSessionPrecondition)
        XCTAssertEqual(session.views.count, 1)

        let view = session.views[0]
        XCTAssertEqual(view.name, "FirstView")
        DDAssertEqual(view.duration, 4 * dt, accuracy: accuracy)
        XCTAssertEqual(view.actionEvents.count, 0)
        XCTAssertEqual(view.resourceEvents.count, 1)
        XCTAssertEqual(view.longTaskEvents.count, 2)
    }

    @available(tvOS, unavailable)
    func testGivenPrewarmedLaunch_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET disabled
        let given = enableRUM(osPrewarmLaunch) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let userSession = try when.then().takeSingle()
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }

    @available(tvOS, unavailable)
    func testGivenPrewarmedLaunch_andBETEnabled_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET enabled
        let given = enableRUM(osPrewarmLaunch) {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let (backgroundSession, userSession) = try when.then().takeTwo()
        assertSuspendedBackgroundSession(session: backgroundSession, expectedSessionPrecondition: .prewarm)
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }

    func testGivenBackgroundLaunch_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET disabled
        let given = enableRUM(backgroundLaunch) { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let userSession = try when.then().takeSingle()
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }

    func testGivenBackgroundLaunch_andBETEnabled_andSuspendedBackgroundSession_whenItGetsResumedByUserSession() throws {
        // Given
        // - BET enabled
        let given = enableRUM(backgroundLaunch) {
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            $0.trackBackgroundEvents = true
        }

        // When
        let when = simulateSuspendedBackgroundSessionResumedByUser(in: given)

        // Then
        let (backgroundSession, userSession) = try when.then().takeTwo()
        assertSuspendedBackgroundSession(session: backgroundSession, expectedSessionPrecondition: .backgroundLaunch)
        assertResumedUserSession(session: userSession, expectedSessionPrecondition: .inactivityTimeout)
    }
}
