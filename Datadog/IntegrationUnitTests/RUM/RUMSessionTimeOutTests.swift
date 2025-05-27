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

class RUMSessionTimeOutTests: RUMSessionTestsBase {
    // MARK: - Foreground session "time out" → track in foreground

    func testGivenUserSession_whenItTimesOut_andNextEventIsTrackedInForeground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSession { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithAutomaticView()
        let given4 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given5 = userSessionWithManualView()
        let given6 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        let expectedViewInRestartedSession = [
            given1: applicationLaunchViewName,
            given2: applicationLaunchViewName,
            given3: automaticViewName,
            given4: automaticViewName,
            given5: manualViewName,
            given6: manualViewName,
        ]

        for given in [given1, given2, given3, given4, given5, given6] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.timeoutSession())
                .and(.trackResource(after: dt1, duration: dt2))
            let when3 = given
                .when(.timeoutSession())
                .and(.trackTwoLongTasks(after1: dt1, after2: dt2))

            for when in [when1, when2, when3] {
                // Then
                // - It tracks "timed out" session:
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertNotNil(session1.applicationStartAction)
                DDAssertEqual(session1.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
                if given == given1 || given == given2 { // session with `ApplicationLaunch` view
                    DDAssertEqual(session1.duration, timeToSDKInit, accuracy: accuracy)
                    XCTAssertEqual(session1.views.count, 1)
                    XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session1.views[0].duration, timeToSDKInit, accuracy: accuracy)
                } else { // session with automatic or manual view
                    DDAssertEqual(session1.duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session1.views.count, 2)
                    XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session1.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session1.views[1].name, (given == given3 || given == given4) ? automaticViewName : manualViewName)
                    DDAssertEqual(session1.views[1].duration, 0, accuracy: accuracy)
                }

                // - It creates new session with restarting the last view for tracking new events:
                XCTAssertNil(session2.applicationStartAction)
                XCTAssertNil(session2.applicationStartupTime)
                DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + sessionTimeoutDuration + dt1, accuracy: accuracy)
                DDAssertEqual(session2.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, expectedViewInRestartedSession[given])
                DDAssertEqual(session2.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
                XCTAssertEqual(session2.views[0].longTaskEvents.count, when == when3 ? 2 : 0)
            }
        }
    }

    func testGivenUserSession_whenItTimesOut_andEntersBackground_andNextEventIsTrackedInForeground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSession { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithAutomaticView()
        let given4 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given5 = userSessionWithManualView()
        let given6 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        let expectedViewInRestartedSession = [
            given1: applicationLaunchViewName,
            given2: applicationLaunchViewName,
            given3: automaticViewName,
            given4: automaticViewName,
            given5: manualViewName,
            given6: manualViewName,
        ]

        for given in [given1, given2, given3, given4, given5, given6] {
            // When
            // - "time out" → BG → FG → event
            let when1 = given
                .when(.timeoutSession())
                .and(.appEntersBackground(after: dt1))
                .and(.appBecomesActive(after: dt2))
                .and(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.timeoutSession())
                .and(.appEntersBackground(after: dt1))
                .and(.appBecomesActive(after: dt2))
                .and(.trackResource(after: dt3, duration: dt4))
            let when3 = given
                .when(.timeoutSession())
                .and(.appEntersBackground(after: dt1))
                .and(.appBecomesActive(after: dt2))
                .and(.trackTwoLongTasks(after1: dt3, after2: dt4))

            for when in [when1, when2, when3] {
                // Then
                // - It tracks "timed out" session:
                let (session1, session2) = try when.then().takeTwo()
                DDAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)

                // - It creates new session with restarting the last view for tracking new events:
                XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                XCTAssertEqual(session2.views.count, 1)
                if given == given3 || given == given4 { // session with automatic view
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + sessionTimeoutDuration + dt1 + dt2, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt3 + dt4, accuracy: accuracy)
                    DDAssertEqual(session2.views[0].duration, dt3 + dt4, accuracy: accuracy)
                } else { // session with `ApplicationLaunch` of manual view
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + sessionTimeoutDuration + dt1 + dt2 + dt3, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt4, accuracy: accuracy)
                    DDAssertEqual(session2.views[0].duration, dt4, accuracy: accuracy)
                }
                XCTAssertEqual(session2.views[0].name, expectedViewInRestartedSession[given])
                XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
                XCTAssertEqual(session2.views[0].longTaskEvents.count, when == when3 ? 2 : 0)
            }
        }
    }

    func testGivenUserSession_whenItEntersBackground_andTimesOut_andNextEventIsTrackedInForeground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSession { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithAutomaticView()
        let given4 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given5 = userSessionWithManualView()
        let given6 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        let expectedViewInRestartedSession = [
            given1: applicationLaunchViewName,
            given2: applicationLaunchViewName,
            given3: automaticViewName,
            given4: automaticViewName,
            given5: manualViewName,
            given6: manualViewName,
        ]

        for given in [given1, given2, given3, given4, given5, given6] {
            // When
            // - BG → "time out" → FG → event
            let when1 = given
                .when(.appEntersBackground(after: dt1))
                .and(.timeoutSession())
                .and(.appBecomesActive(after: dt2))
                .and(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.appEntersBackground(after: dt1))
                .and(.timeoutSession())
                .and(.appBecomesActive(after: dt2))
                .and(.trackResource(after: dt3, duration: dt4))
            let when3 = given
                .when(.appEntersBackground(after: dt1))
                .and(.timeoutSession())
                .and(.appBecomesActive(after: dt2))
                .and(.trackTwoLongTasks(after1: dt3, after2: dt4))

            for when in [when1, when2, when3] {
                // Then
                // - It tracks "timed out" session:
                let (session1, session2) = try when.then().takeTwo()
                DDAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)

                // - It creates new session with restarting the last view for tracking new events:
                XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                XCTAssertEqual(session2.views.count, 1)
                if given == given3 || given == given4 { // session with automatic view
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1 + sessionTimeoutDuration + dt2, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt3 + dt4, accuracy: accuracy)
                    DDAssertEqual(session2.views[0].duration, dt3 + dt4, accuracy: accuracy)
                } else { // session with `ApplicationLaunch` of manual view
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1 + sessionTimeoutDuration + dt2 + dt3, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt4, accuracy: accuracy)
                    DDAssertEqual(session2.views[0].duration, dt4, accuracy: accuracy)
                }
                XCTAssertEqual(session2.views[0].name, expectedViewInRestartedSession[given])
                XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
                XCTAssertEqual(session2.views[0].longTaskEvents.count, when == when3 ? 2 : 0)
            }
        }
    }

    // MARK: - Foreground session "time out" → track in background

    func testGivenUserSession_whenItTimesOut_andNextEventIsTrackedInBackground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSessionWithAutomaticView()
        let given3 = userSessionWithManualView()

        for given in [given1, given2, given3] {
            // When
            // - "time out" → BG
            let when1 = given
                .when(.timeoutSession())
                .and(.appEntersBackground(after: dt1))

            for when in [
                when1.and(.trackTwoActions(after1: dt2, after2: dt3)),
                when1.and(.trackResource(after: dt2, duration: dt3)),
                when1.and(.trackTwoLongTasks(after1: dt2, after2: dt3)),
            ] {
                // Then
                // - It only tracks "timed out" session (background events are skipped due to BET disabled):
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                if given == given1 { // session with `ApplicationLaunch` view
                    DDAssertEqual(session.duration, timeToSDKInit, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit, accuracy: accuracy)
                } else { // session with atomatic or manual view
                    DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given2) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, 0, accuracy: accuracy)
                }
            }

            // When
            // - BG → "time out"
            let when2 = given
                .and(.appEntersBackground(after: dt1))
                .when(.timeoutSession())

            for when in [
                when2.and(.trackTwoActions(after1: dt2, after2: dt3)),
                when2.and(.trackResource(after: dt2, duration: dt3)),
                when2.and(.trackTwoLongTasks(after1: dt2, after2: dt3)),
            ] {
                // Then
                // - It only tracks "timed out" session (background events are skipped due to BET disabled):
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                if given == given1 { // session with `ApplicationLaunch` view
                    DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                } else if given == given2 { // session with atomatic view
                    DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given2) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, dt1, accuracy: accuracy)
                } else { // session with manual view
                    DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given2) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, 0, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenUserSession_andBETEnabled_whenItTimesOut_andNextEventIsTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = userSession { $0.trackBackgroundEvents = true }
        let given2 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        for given in [given1, given2, given3] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.appEntersBackground(after: dt1))
            let when2 = given
                .and(.appEntersBackground(after: dt1))
                .when(.timeoutSession())

            for when in [when1, when2] {
                // When
                // - actions or resource
                let when1 = when.and(.trackTwoActions(after1: dt2, after2: dt3))
                let when2 = when.and(.trackResource(after: dt2, duration: dt3))

                for when in [when1, when2] {
                    // Then
                    // - It tracks "timed out" session (same as with BET disabled):
                    let (session1, session2) = try when.then().takeTwo()
                    XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)

                    // - It creates new session for tracking background events:
                    XCTAssertNil(session2.applicationStartAction)
                    XCTAssertNil(session2.applicationStartupTime)
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + sessionTimeoutDuration + dt1 + dt2, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt3, accuracy: accuracy)
                    XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                    XCTAssertEqual(session2.views.count, 1)
                    XCTAssertEqual(session2.views[0].name, backgroundViewName)
                    DDAssertEqual(session2.views[0].duration, dt3, accuracy: accuracy)
                    XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                    XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
                }

                // When
                // - long tasks
                let when3 = when.and(.trackTwoLongTasks(after1: dt2, after2: dt3))

                // Then
                // - It only tracks "timed out" session (long tasks are skipped in background regardless BET enabled):
                let session = try when3.then().takeSingle()
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            }
        }
    }

    // MARK: - Background session "time out" → track in background

    func testGivenBackgroundSession_whenItTimesOut_andNextEventIsTrackedInBackground() throws {
        // Given
        let given1 = backgroundSession()
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession()
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.timeoutSession())
                .and(.trackResource(after: dt3, duration: dt4))
            let when3 = given
                .when(.timeoutSession())
                .when(.trackTwoLongTasks(after1: dt3, after2: dt4))

            for when in [when1, when2, when3] {
                // Then
                // - No session is tracked because BET is disabled:
                let sessions = try when.then()
                XCTAssertTrue(sessions.isEmpty)
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItTimesOut_andNextEventIsTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.timeoutSession())
                .and(.trackResource(after: dt3, duration: dt4))

            for when in [when1, when2] {
                // Then
                // - It tracks "timed out" background session:
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertNil(session1.applicationStartAction)
                XCTAssertNil(session1.applicationStartupTime)
                DDAssertEqual(session1.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session1.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session1.views.count, 1)
                XCTAssertEqual(session1.views[0].name, backgroundViewName)
                DDAssertEqual(session1.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session1.views[0].resourceEvents.count, 1)

                // - It creates new session for tracking background events:
                XCTAssertNil(session2.applicationStartAction)
                XCTAssertNil(session2.applicationStartupTime)
                DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + sessionTimeoutDuration + dt3, accuracy: accuracy)
                DDAssertEqual(session2.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, backgroundViewName)
                DDAssertEqual(session2.views[0].duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session2.views[0].actionEvents.count, when == when1 ? 2 : 0)
                XCTAssertEqual(session2.views[0].resourceEvents.count, when == when2 ? 1 : 0)
            }

            // When
            let when3 = given
                .when(.timeoutSession())
                .when(.trackTwoLongTasks(after1: dt2, after2: dt3))

            // Then
            // - It only tracks "timed out" session (long tasks are skipped in background regardless BET enabled):
            let session = try when3.then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
            DDAssertEqual(session.duration, dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, backgroundViewName)
            DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            XCTAssertEqual(session.views[0].resourceEvents.count, 1)
        }
    }

    // MARK: - Background session "time out" → track in foreground

    func testGivenBackgroundSession_whenItTimesOut_andNextEventIsTrackedInForeground() throws {
        // Given
        let given1 = backgroundSession()
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession()
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.appBecomesActive(after: dt3))
            let when2 = given
                .and(.appBecomesActive(after: dt3))
                .when(.timeoutSession())

            for when in [when1, when2] {
                // When
                let when1 = when.and(.trackTwoActions(after1: dt4, after2: dt5))
                let when2 = when.and(.trackResource(after: dt4, duration: dt5))
                let when3 = when.and(.trackTwoLongTasks(after1: dt4, after2: dt5))

                for when in [when1, when2, when3] {
                    // Then
                    // - It only tracks foreground session ("timed out" session is skipped due to BET disabled):
                    let session = try when.then().takeSingle()
                    XCTAssertNil(session.applicationStartAction)
                    XCTAssertNil(session.applicationStartupTime)
                    DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + sessionTimeoutDuration + dt3 + dt4, accuracy: accuracy)
                    DDAssertEqual(session.duration, dt5, accuracy: accuracy)
                    XCTAssertEqual(session.sessionPrecondition, .inactivityTimeout)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, dt5, accuracy: accuracy)
                    XCTAssertEqual(session.views[0].actionEvents.count, when == when1 ? 2 : 0)
                    XCTAssertEqual(session.views[0].resourceEvents.count, when == when2 ? 1 : 0)
                    XCTAssertEqual(session.views[0].longTaskEvents.count, when == when3 ? 2 : 0)
                }
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItTimesOut_andNextEventIsTrackedInForeground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.appBecomesActive(after: dt3))
            let when2 = given
                .and(.appBecomesActive(after: dt3))
                .when(.timeoutSession())

            for when in [when1, when2] {
                // When
                let when1 = when.and(.trackResource(after: dt4, duration: dt5))
                let when2 = when.and(.trackTwoActions(after1: dt4, after2: dt5))
                let when3 = when.and(.trackTwoLongTasks(after1: dt4, after2: dt5))

                for when in [when1, when2, when3] {
                    // Then
                    // - It only tracks "timed out" background session (foreground events are skipped due to "no view"):
                    let session = try when.then().takeSingle()
                    XCTAssertNil(session.applicationStartAction)
                    XCTAssertNil(session.applicationStartupTime)
                    DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                    DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                    XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, backgroundViewName)
                    DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenBackgroundSession_whenItTimesOut_andViewIsTrackedInForeground() throws {
        // Given
        let given1 = backgroundSession { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.appBecomesActive(after: dt3))
            let when2 = given
                .and(.appBecomesActive(after: dt3))
                .when(.timeoutSession())

            for when in [when1, when2] {
                // When
                let when1 = when
                    .and(.startAutomaticView(after: dt4, viewController: automaticView))
                    .and(.stopAutomaticView(after: dt5, viewController: automaticView))
                let when2 = when
                    .and(.startManualView(after: dt4, viewName: manualViewName, viewKey: "manual-view"))
                    .and(.stopManualView(after: dt5, viewKey: "manual-view"))

                for when in [when1, when2] {
                    // Then
                    // - It only tracks foreground session ("timed out" background session is skipped due to BET disabled):
                    let session = try when.then().takeSingle()
                    XCTAssertNil(session.applicationStartAction)
                    XCTAssertNil(session.applicationStartupTime)
                    DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + sessionTimeoutDuration + dt3 + dt4, accuracy: accuracy)
                    DDAssertEqual(session.duration, dt5, accuracy: accuracy)
                    XCTAssertEqual(session.sessionPrecondition, .inactivityTimeout)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, when == when1 ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[0].duration, dt5, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItTimesOut_andViewIsTrackedInForeground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession {
            $0.trackBackgroundEvents = true
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession {
            $0.trackBackgroundEvents = true
            $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.timeoutSession())
                .and(.appBecomesActive(after: dt3))
            let when2 = given
                .and(.appBecomesActive(after: dt3))
                .when(.timeoutSession())

            for when in [when1, when2] {
                // When
                let when1 = when
                    .and(.startAutomaticView(after: dt4, viewController: automaticView))
                    .and(.stopAutomaticView(after: dt5, viewController: automaticView))
                let when2 = when
                    .and(.startManualView(after: dt4, viewName: manualViewName, viewKey: "manual-view"))
                    .and(.stopManualView(after: dt5, viewKey: "manual-view"))

                for when in [when1, when2] {
                    // Then
                    // - It tracks "timed out" background session:
                    let (session1, session2) = try when.then().takeTwo()
                    XCTAssertNil(session1.applicationStartAction)
                    XCTAssertNil(session1.applicationStartupTime)
                    DDAssertEqual(session1.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                    DDAssertEqual(session1.duration, dt2, accuracy: accuracy)
                    XCTAssertEqual(session1.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                    XCTAssertEqual(session1.views.count, 1)
                    XCTAssertEqual(session1.views[0].name, backgroundViewName)
                    DDAssertEqual(session1.views[0].duration, dt2, accuracy: accuracy)
                    XCTAssertEqual(session1.views[0].resourceEvents.count, 1)

                    // - It creates new session for tracking view in foreground:
                    XCTAssertNil(session2.applicationStartAction)
                    XCTAssertNil(session2.applicationStartupTime)
                    DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + sessionTimeoutDuration + dt3 + dt4, accuracy: accuracy)
                    DDAssertEqual(session2.duration, dt5, accuracy: accuracy)
                    XCTAssertEqual(session2.sessionPrecondition, .inactivityTimeout)
                    XCTAssertEqual(session2.views.count, 1)
                    XCTAssertEqual(session2.views[0].name, when == when1 ? automaticViewName : manualViewName)
                    DDAssertEqual(session2.views[0].duration, dt5, accuracy: accuracy)
                }
            }
        }
    }
}
