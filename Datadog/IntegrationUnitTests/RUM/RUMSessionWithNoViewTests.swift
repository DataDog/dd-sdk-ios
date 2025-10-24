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

class RUMSessionWithNoViewTests: RUMSessionTestsBase {
    // MARK: - Scenarios for session with no view

    /// Creates `"background_launch"` session that is in foreground but has no view.
    /// ```
    /// [BG:Background] --> [FG:(no view)]
    /// ```
    func backgroundSessionWithResourceThatBecameActive(
        resourceStartAfter: TimeInterval,
        resourceDuration: TimeInterval,
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return backgroundSessionWithResource(resourceStartAfter: dt1, resourceDuration: dt2, rumSetup: rumSetup)
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.appDisplaysFirstFrame())
    }

    /// Creates `"prewarm"` session that is in foreground but has no view.
    /// ```
    /// [BG:Background] --> [FG:(no view)]
    /// ```
    func prewarmedSessionWithResourceThatBecameActive(
        resourceStartAfter: TimeInterval,
        resourceDuration: TimeInterval,
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return prewarmedSessionWithResource(resourceStartAfter: dt1, resourceDuration: dt2, rumSetup: rumSetup)
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.appDisplaysFirstFrame())
    }

    /// Creates `"user_app_launch"` session that is now in background.
    /// ```
    /// [FG:ApplicationLaunch] --> [BG:(no view)]
    /// ```
    func userSessionThatEnteredBackground(
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return userSession(rumSetup: rumSetup)
            .and(.appEntersBackground(after: timeToAppEnterBackground))
    }

    /// Creates `"user_app_launch"` session which started automatci view that is now in background.
    /// ```
    /// [FG:ApplicationLaunch] --> [FG:AutomaticView] --> [BG:(no view)]
    /// ```
    func userSessionWithAutomaticViewThatEnteredBackground(
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return userSessionWithAutomaticView(rumSetup: rumSetup)
            .and(.appEntersBackground(after: timeToAppEnterBackground))
    }

    // MARK: - Session in foreground with no view

    func testGivenBackgroundOrPrewarmedSessionThatBecameActive_whenEventsAreTracked() throws {
        // Given
        let given1 = backgroundSessionWithResourceThatBecameActive(resourceStartAfter: dt1, resourceDuration: dt2)
        let given2 = prewarmedSessionWithResourceThatBecameActive(resourceStartAfter: dt1, resourceDuration: dt2)

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.trackResource(after: dt3, duration: dt4))
            let when3 = given
                .when(.trackTwoLongTasks(after1: dt3, after2: dt4))

            for when in [when1, when2, when3] {
                // Then
                // - it only tracks Background view (foreground events are dropped due to "no view")
                let session = try when.then().takeSingle()
                if session.sessionPrecondition == .prewarm {
                    XCTAssertNotNil(session.ttidEvent)
                    DDAssertEqual(session.timeToInitialDisplay, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2 - 0.1 , accuracy: accuracy)
                } else {
                    XCTAssertNil(session.ttidEvent)
                    XCTAssertNil(session.timeToInitialDisplay)
                }
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, backgroundViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }
    }

    // MARK: - Session in background with no view

    func testGivenBackgroundOrPrewarmedSession_whenEventsAreTracked() throws {
        // Given
        // - BET disabled
        let given1 = backgroundSession()
        let given2 = prewarmedSession()

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when3 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

            for when in [when1, when2, when3] {
                // Then
                let sessions = try when.then()
                XCTAssertTrue(sessions.isEmpty)
            }
        }

        // Given
        // - BET enabled
        let given3 = backgroundSession { $0.trackBackgroundEvents = true }
        let given4 = prewarmedSession { $0.trackBackgroundEvents = true }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.ttidEvent)
                XCTAssertNil(session.timeToInitialDisplay)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, given == given3 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, backgroundViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }

        for given in [given3, given4] {
            // When
            let when = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    func testGivenUserSessionThatEnteredBackground_whenEventsAreTracked() throws {
        // Given
        // - BET disabled
        let given1 = userSessionThatEnteredBackground()

        // When
        let when1 = given1
            .when(.trackTwoActions(after1: dt1, after2: dt2))
        let when2 = given1
            .when(.trackResource(after: dt1, duration: dt2))
        let when3 = given1
            .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

        for when in [when1, when2, when3] {
            // Then
            // - it only tracks ApplicationLaunch view (background events are dropped due to BET disabled)
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.ttidEvent)
            DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
            DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
        }

        // Given
        // - BET enabled
        let given3 = userSessionThatEnteredBackground { $0.trackBackgroundEvents = true }

        // When
        let when4 = given3
            .when(.trackTwoActions(after1: dt1, after2: dt2))
        let when5 = given3
            .when(.trackResource(after: dt1, duration: dt2))

        for when in [when4, when5] {
            // Then
            // - it tracks ApplicationLaunch and Background views
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.ttidEvent)
            DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
            DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, backgroundViewName)
            DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
        }

        // When
        let when6 = given3
            .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

        // Then
        // - it only tracks ApplicationLaunch view (Long Tasks are not tracked in background even if BET is enabled)
        let session = try when6.then().takeSingle()
        XCTAssertNotNil(session.ttidEvent)
        DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
        DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
        DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
        XCTAssertEqual(session.views.count, 1)
        XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
        DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
    }

    func testGivenUserSessionWithAutomaticViewThatEnteredBackground_whenEventsAreTracked() throws {
        // Given
        // - BET disabled
        let given1 = userSessionWithAutomaticViewThatEnteredBackground()

        // When
        let when1 = given1
            .when(.trackTwoActions(after1: dt1, after2: dt2))
        let when2 = given1
            .when(.trackResource(after: dt1, duration: dt2))
        let when3 = given1
            .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

        for when in [when1, when2, when3] {
            // Then
            // - it only tracks ApplicationLaunch + AutomaticView views (background events are dropped due to BET disabled)
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.ttidEvent)
            DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
            DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 2)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, automaticViewName)
            DDAssertEqual(session.views[1].duration, timeToAppEnterBackground, accuracy: accuracy)
        }

        // Given
        // - BET enabled
        let given3 = userSessionWithAutomaticViewThatEnteredBackground { $0.trackBackgroundEvents = true }

        // When
        let when4 = given3
            .when(.trackTwoActions(after1: dt1, after2: dt2))
        let when5 = given3
            .when(.trackResource(after: dt1, duration: dt2))

        for when in [when4, when5] {
            // Then
            // - it tracks ApplicationLaunch + AutomaticView + Background views
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.ttidEvent)
            DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
            DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground + dt1 + dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 3)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
            XCTAssertEqual(session.views[1].name, automaticViewName)
            DDAssertEqual(session.views[1].duration, timeToAppEnterBackground, accuracy: accuracy)
            XCTAssertEqual(session.views[2].name, backgroundViewName)
            DDAssertEqual(session.views[2].duration, dt2, accuracy: accuracy)
        }

        // When
        let when6 = given3
            .when(.trackTwoLongTasks(after1: dt1, after2: dt2))

        // Then
        // - it only tracks ApplicationLaunch + AutomaticView views (Long Tasks are not tracked in background even if BET is enabled)
        let session = try when6.then().takeSingle()
        XCTAssertNotNil(session.ttidEvent)
        DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
        DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
        DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + timeToAppEnterBackground, accuracy: accuracy)
        XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
        XCTAssertEqual(session.views.count, 2)
        XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
        DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
        XCTAssertEqual(session.views[1].name, automaticViewName)
        DDAssertEqual(session.views[1].duration, timeToAppEnterBackground, accuracy: accuracy)
    }
}
