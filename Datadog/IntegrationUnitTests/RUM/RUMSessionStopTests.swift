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

class RUMSessionStopTests: RUMSessionTestsBase {
    // MARK: - Foreground session "stop" → track in foreground

    func testGivenUserSession_whenItIsStopped_andActionIsTrackedInForeground() throws {
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
            let when = given
                .and(.flushDatadogContext())
                .when(.stopSession(after: dt1))
                .and(.trackTwoActions(after1: dt2, after2: dt3))

            // Then
            // - It tracks "stopped" session:
            let (session1, session2) = try when.then().takeTwo()
            XCTAssertNotNil(session1.ttidEvent)
            DDAssertEqual(session1.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
            DDAssertEqual(session1.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session1.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
            XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
            if given == given1 || given == given2 { // session with `ApplicationLaunch` view
                XCTAssertEqual(session1.views.count, 1)
                XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session1.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
            } else { // session with atomatic or manual view
                XCTAssertEqual(session1.views.count, 2)
                XCTAssertEqual(session1.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session1.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                XCTAssertEqual(session1.views[1].name, (given == given3 || given == given4) ? automaticViewName : manualViewName)
                DDAssertEqual(session1.views[1].duration, dt1, accuracy: accuracy)
            }

            // - It creates new session with restarting the last view for tracking new events:
            XCTAssertNil(session2.ttidEvent)
            XCTAssertNil(session2.timeToInitialDisplay)
            DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
            DDAssertEqual(session2.duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
            XCTAssertEqual(session2.views.count, 1)
            XCTAssertEqual(session2.views[0].name, expectedViewInRestartedSession[given])
            DDAssertEqual(session2.views[0].duration, dt3, accuracy: accuracy)
            XCTAssertEqual(session2.views[0].actionEvents.count, 2)
        }
    }

    func testGivenUserSession_whenItIsStopped_andOtherEventsAreTrackedInForeground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSession { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithAutomaticView()
        let given4 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given5 = userSessionWithManualView()
        let given6 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        for given in [given1, given2, given3, given4, given5, given6] {
            // When
            let when2 = given
                .and(.flushDatadogContext())
                .when(.stopSession(after: dt1))
                .and(.trackResource(after: dt2, duration: dt3))
            let when3 = given
                .and(.flushDatadogContext())
                .when(.stopSession(after: dt1))
                .and(.trackTwoLongTasks(after1: dt2, after2: dt3))

            for when in [when2, when3] {
                // Then
                // - It only tracks "stopped" session:
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.ttidEvent)
                DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                if given == given1 || given == given2 { // session with `ApplicationLaunch` view
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                } else { // session with atomatic or manual view
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given3 || given == given4) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, dt1, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenUserSession_whenItIsStoppedBeforeOrAfterEnteringBackground_andActionIsTrackedInForeground() throws {
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
            // - "stop" → BG → FG → action event
            let when1 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoActions(after1: dt4, after2: dt5))
            // When
            // - BG → "stop" → FG → action event
            let when2 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoActions(after1: dt4, after2: dt5))

            for when in [when1, when2] {
                // Then
                // - It tracks "stopped" session
                // - It tracks action in new session with restarting the last view
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, expectedViewInRestartedSession[given])
            }
        }
    }

    func testGivenUserSession_whenItIsStoppedBeforeOrAfterEnteringBackground_andOtherEventsAreTrackedInForeground() throws {
        // Given
        // - session with ApplicationLaunch or manual view
        let given1 = userSession()
        let given2 = userSession { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithManualView()
        let given4 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        for given in [given1, given2, given3, given4] {
            // When
            // - "stop" → BG → FG → other events
            let when1 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when2 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            // When
            // - BG → "stop" → FG → other events
            let when3 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when4 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            for when in [when1, when2, when3, when4] {
                // Then
                // - It tracks "stopped" session (events other than action are dropped after `sessionStop()` unless a view is started explicitly)
                let session = try when.then().takeSingle()
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            }
        }

        // Given
        // - session with automatic view
        let given5 = userSessionWithAutomaticView()
        let given6 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }

        for given in [given5, given6] {
            // When
            // - "stop" → BG → FG → other events
            let when1 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when2 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            // When
            // - BG → "stop" → FG → other events
            let when3 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when4 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.appBecomesActive(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            for when in [when1, when2, when3, when4] {
                // Then
                // - It tracks "stopped" session
                // - It tracks other events in new session because view was started by "→ FG" transition
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, automaticViewName)
            }
        }
    }

    // MARK: - Foreground session "stop" → track in background

    func testGivenUserSession_whenItIsStopped_andNextEventIsTrackedInBackground() throws {
        // Given
        let given1 = userSession()
        let given2 = userSessionWithAutomaticView()
        let given3 = userSessionWithManualView()

        for given in [given1, given2, given3] {
            // When
            // - "stop" → BG
            let when1 = given
                .and(.flushDatadogContext())
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))

            for when in [
                when1.and(.trackTwoActions(after1: dt3, after2: dt4)),
                when1.and(.trackResource(after: dt3, duration: dt4)),
                when1.and(.trackTwoLongTasks(after1: dt3, after2: dt4)),
            ] {
                // Then
                // - It only tracks "stopped" session (background events are skipped due to BET disabled):
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.ttidEvent)
                DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                if given == given1 { // session with `ApplicationLaunch` view
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                } else { // session with atomatic or manual view
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given2) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, dt1, accuracy: accuracy)
                }
            }

            // When
            // - BG → "stop"
            let when2 = given
                .when(.appEntersBackground(after: dt1))
                .and(.flushDatadogContext())
                .and(.stopSession(after: dt2))

            for when in [
                when2.and(.trackTwoActions(after1: dt3, after2: dt4)),
                when2.and(.trackResource(after: dt3, duration: dt4)),
                when2.and(.trackTwoLongTasks(after1: dt3, after2: dt4)),
            ] {
                // Then
                // - It only tracks "stopped" session (background events are skipped due to BET disabled):
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.ttidEvent)
                DDAssertEqual(session.timeToInitialDisplay, timeToInitialDisplay, accuracy: accuracy)
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
                    DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                    XCTAssertEqual(session.views.count, 2)
                    XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                    DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive, accuracy: accuracy)
                    XCTAssertEqual(session.views[1].name, (given == given2) ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[1].duration, dt1 + dt2, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenUserSession_andBETEnabled_whenItIsStopped_andActionIsTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = userSession { $0.trackBackgroundEvents = true }
        let given2 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        for given in [given1, given2, given3] {
            // When
            let when1 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
                .and(.trackTwoActions(after1: dt3, after2: dt4))
            let when2 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))
                .and(.trackTwoActions(after1: dt3, after2: dt4))

            for when in [when1, when2] {
                // Then
                // - It tracks "stopped" session (same as with BET disabled):
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertEqual(session1.sessionPrecondition, .userAppLaunch)

                // - It creates new session for tracking background events:
                XCTAssertNil(session2.ttidEvent)
                XCTAssertNil(session2.timeToInitialDisplay)
                DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1 + dt2 + dt3, accuracy: accuracy)
                DDAssertEqual(session2.duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, backgroundViewName)
                DDAssertEqual(session2.views[0].duration, dt4, accuracy: accuracy)
                XCTAssertEqual(session2.views[0].actionEvents.count, 2)
            }
        }
    }

    func testGivenUserSession_andBETEnabled_whenItIsStopped_andOtherEventsAreTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = userSession { $0.trackBackgroundEvents = true }
        let given2 = userSessionWithAutomaticView { $0.trackBackgroundEvents = true }
        let given3 = userSessionWithManualView { $0.trackBackgroundEvents = true }

        for given in [given1, given2, given3] {
            // When
            let when1 = given
                .when(.stopSession(after: dt1))
                .and(.appEntersBackground(after: dt2))
            let when2 = given
                .when(.appEntersBackground(after: dt1))
                .and(.stopSession(after: dt2))

            for when in [when1, when2] {
                // When
                let when1 = when.and(.trackResource(after: dt3, duration: dt4))
                let when2 = when.and(.trackTwoLongTasks(after1: dt3, after2: dt4))

                for when in [when1, when2] {
                    // Then
                    // - It tracks "stopped" session (events other than action are dropped after `sessionStop()` unless a view is started explicitly)
                    let session = try when.then().takeSingle()
                    XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                }
            }
        }
    }

    // MARK: - Background session "stop" → track in background

    func testGivenBackgroundSession_whenItIsStopped_andNextEventIsTrackedInBackground() throws {
        // Given
        let given1 = backgroundSession()
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession()
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.trackTwoActions(after1: dt4, after2: dt5))
            let when2 = given
                .when(.stopSession(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when3 = given
                .when(.stopSession(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            for when in [when1, when2, when3] {
                // Then
                // - No session is tracked because BET is disabled:
                let sessions = try when.then()
                XCTAssertTrue(sessions.isEmpty)
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItIsStopped_andActionIsTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when = given
                .when(.stopSession(after: dt3))
                .and(.trackTwoActions(after1: dt4, after2: dt5))

            // Then
            // - It tracks "stopped" background session:
            let (session1, session2) = try when.then().takeTwo()
            XCTAssertNil(session1.ttidEvent)
            XCTAssertNil(session1.timeToInitialDisplay)
            DDAssertEqual(session1.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
            DDAssertEqual(session1.duration, dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session1.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
            XCTAssertEqual(session1.views.count, 1)
            XCTAssertEqual(session1.views[0].name, backgroundViewName)
            DDAssertEqual(session1.views[0].duration, dt2 + dt3, accuracy: accuracy)
            XCTAssertEqual(session1.views[0].resourceEvents.count, 1)

            // - It creates new session for tracking background events:
            XCTAssertNil(session2.ttidEvent)
            XCTAssertNil(session2.timeToInitialDisplay)
            DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + dt3 + dt4, accuracy: accuracy)
            DDAssertEqual(session2.duration, dt5, accuracy: accuracy)
            XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
            XCTAssertEqual(session2.views.count, 1)
            XCTAssertEqual(session2.views[0].name, backgroundViewName)
            DDAssertEqual(session2.views[0].duration, dt5, accuracy: accuracy)
            XCTAssertEqual(session2.views[0].actionEvents.count, 2)
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItIsStopped_andOtherEventsAreTrackedInBackground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.trackResource(after: dt4, duration: dt5))
            let when2 = given
                .when(.stopSession(after: dt3))
                .and(.trackTwoLongTasks(after1: dt4, after2: dt5))

            for when in [when1, when2] {
                // Then
                // - It tracks "stopped" session (events other than action are dropped after `sessionStop()`):
                let session = try when.then().takeSingle()
                XCTAssertNil(session.ttidEvent)
                XCTAssertNil(session.timeToInitialDisplay)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, backgroundViewName)
                DDAssertEqual(session.views[0].duration, dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.views[0].resourceEvents.count, 1)
            }
        }
    }

    // MARK: - Background session "stop" → track in foreground

    func testGivenBackgroundSession_whenItIsStopped_andNextEventIsTrackedInForeground() throws {
        // Given
        let given1 = backgroundSession()
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession()
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.appBecomesActive(after: dt4))
            let when2 = given
                .when(.appBecomesActive(after: dt3))
                .and(.stopSession(after: dt4))

            for when in [when1, when2] {
                // When
                let when1 = when.and(.trackTwoActions(after1: dt5, after2: dt6))
                let when2 = when.and(.trackResource(after: dt5, duration: dt6))
                let when3 = when.and(.trackTwoLongTasks(after1: dt5, after2: dt6))

                for when in [when1, when2, when3] {
                    // Then
                    // - No session is tracked (background events are skipped due to BET disabled; foreground events are skipped due to "no view"):
                    let sessions = try when.then()
                    XCTAssertTrue(sessions.isEmpty)
                }
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItIsStopped_andNextEventIsTrackedInForeground() throws {
        // Given
        // - BET enabled
        let given1 = backgroundSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.trackBackgroundEvents = true }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            // - "stop" → BG
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.appBecomesActive(after: dt4))

            for when in [
                when1.and(.trackResource(after: dt5, duration: dt6)),
                when1.and(.trackTwoActions(after1: dt5, after2: dt6)),
                when1.and(.trackTwoLongTasks(after1: dt5, after2: dt6)),
            ] {
                // Then
                // - It only tracks "stopped" background session (foreground events are skipped due to "no view"):
                let session = try when.then().takeSingle()
                XCTAssertNil(session.ttidEvent)
                XCTAssertNil(session.timeToInitialDisplay)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, backgroundViewName)
                DDAssertEqual(session.views[0].duration, dt2 + dt3, accuracy: accuracy)
            }

            // When
            // - BG → "stop"
            let when2 = given
                .when(.appBecomesActive(after: dt3))
                .and(.stopSession(after: dt4))

            for when in [
                when2.and(.trackResource(after: dt5, duration: dt6)),
                when2.and(.trackTwoActions(after1: dt5, after2: dt6)),
                when2.and(.trackTwoLongTasks(after1: dt5, after2: dt6)),
            ] {
                // Then
                // - It only tracks "stopped" background session (foreground events are skipped due to "no view"):
                let session = try when.then().takeSingle()
                XCTAssertNil(session.ttidEvent)
                XCTAssertNil(session.timeToInitialDisplay)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, backgroundViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenBackgroundSession_whenItIsStopped_andViewIsTrackedInForeground() throws {
        // Given
        let given1 = backgroundSession { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }
            .and(.trackResource(after: dt1, duration: dt2))
        let given2 = prewarmedSession { $0.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate() }
            .and(.trackResource(after: dt1, duration: dt2))

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.appBecomesActive(after: dt4))
            let when2 = given
                .when(.appBecomesActive(after: dt3))
                .and(.stopSession(after: dt4))

            for when in [when1, when2] {
                // When
                let when1 = when
                    .and(.startAutomaticView(after: dt5, viewController: automaticView))
                    .and(.stopAutomaticView(after: dt6, viewController: automaticView))
                let when2 = when
                    .and(.startManualView(after: dt5, viewName: manualViewName, viewKey: "manual-view"))
                    .and(.stopManualView(after: dt6, viewKey: "manual-view"))

                for when in [when1, when2] {
                    // Then
                    // - It only tracks foreground session ("stopped" background session is skipped due to BET disabled):
                    let session = try when.then().takeSingle()
                    XCTAssertNil(session.ttidEvent)
                    XCTAssertNil(session.timeToInitialDisplay)
                    DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + dt3 + dt4 + dt5, accuracy: accuracy)
                    DDAssertEqual(session.duration, dt6, accuracy: accuracy)
                    XCTAssertEqual(session.sessionPrecondition, .explicitStop)
                    XCTAssertEqual(session.views.count, 1)
                    XCTAssertEqual(session.views[0].name, when == when1 ? automaticViewName : manualViewName)
                    DDAssertEqual(session.views[0].duration, dt6, accuracy: accuracy)
                }
            }
        }
    }

    func testGivenBackgroundSession_andBETEnabled_whenItIsStopped_andViewIsTrackedInForeground() throws {
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
            // - "stop" → BG
            let when1 = given
                .when(.stopSession(after: dt3))
                .and(.appBecomesActive(after: dt4))
                .and(.startAutomaticView(after: dt5, viewController: automaticView))
                .and(.stopAutomaticView(after: dt6, viewController: automaticView))
            let when2 = given
                .when(.stopSession(after: dt3))
                .and(.appBecomesActive(after: dt4))
                .and(.startManualView(after: dt5, viewName: manualViewName, viewKey: "manual-view"))
                .and(.stopManualView(after: dt6, viewKey: "manual-view"))

            for when in [when1, when2] {
                // Then
                // - It tracks "stopped" background session:
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertNil(session1.ttidEvent)
                XCTAssertNil(session1.timeToInitialDisplay)
                DDAssertEqual(session1.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session1.duration, dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session1.views.count, 1)
                XCTAssertEqual(session1.views[0].name, backgroundViewName)
                DDAssertEqual(session1.views[0].duration, dt2 + dt3, accuracy: accuracy)
                XCTAssertEqual(session1.views[0].resourceEvents.count, 1)

                // - It creates new session for tracking view in foreground:
                XCTAssertNil(session2.ttidEvent)
                XCTAssertNil(session2.timeToInitialDisplay)
                DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + dt3 + dt4 + dt5, accuracy: accuracy)
                DDAssertEqual(session2.duration, dt6, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, when == when1 ? automaticViewName : manualViewName)
                DDAssertEqual(session2.views[0].duration, dt6, accuracy: accuracy)
            }

            // When
            // - BG → "stop"
            let when3 = given
                .when(.appBecomesActive(after: dt3))
                .and(.stopSession(after: dt4))
                .and(.startAutomaticView(after: dt5, viewController: automaticView))
                .and(.stopAutomaticView(after: dt6, viewController: automaticView))
            let when4 = given
                .when(.appBecomesActive(after: dt3))
                .and(.stopSession(after: dt4))
                .and(.startManualView(after: dt5, viewName: manualViewName, viewKey: "manual-view"))
                .and(.stopManualView(after: dt6, viewKey: "manual-view"))

            for when in [when3, when4] {
                // Then
                // - It tracks "stopped" background session:
                let (session1, session2) = try when.then().takeTwo()
                XCTAssertNil(session1.ttidEvent)
                XCTAssertNil(session1.timeToInitialDisplay)
                DDAssertEqual(session1.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
                DDAssertEqual(session1.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session1.sessionPrecondition, given == given1 ? .backgroundLaunch : .prewarm)
                XCTAssertEqual(session1.views.count, 1)
                XCTAssertEqual(session1.views[0].name, backgroundViewName)
                DDAssertEqual(session1.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session1.views[0].resourceEvents.count, 1)

                // - It creates new session for tracking view in foreground:
                XCTAssertNil(session2.ttidEvent)
                XCTAssertNil(session2.timeToInitialDisplay)
                DDAssertEqual(session2.sessionStartDate, processLaunchDate + timeToSDKInit + dt1 + dt2 + dt3 + dt4 + dt5, accuracy: accuracy)
                DDAssertEqual(session2.duration, dt6, accuracy: accuracy)
                XCTAssertEqual(session2.sessionPrecondition, .explicitStop)
                XCTAssertEqual(session2.views.count, 1)
                XCTAssertEqual(session2.views[0].name, when == when3 ? automaticViewName : manualViewName)
                DDAssertEqual(session2.views[0].duration, dt6, accuracy: accuracy)
            }
        }
    }
}
