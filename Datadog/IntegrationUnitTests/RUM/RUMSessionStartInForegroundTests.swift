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

class RUMSessionStartInForegroundTests: RUMSessionTestsBase {
    // MARK: - Scenarios for enabling RUM vs application state and launch type

    private func enableRUMBeforeAppBecomesActive(_ launchType: AppRunner.ProcessLaunchType, rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: launchType))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
            .and(.appBecomesActive(after: timeToAppBecomeActive))
    }

    private func enableRUMAfterAppBecomesActive(_ launchType: AppRunner.ProcessLaunchType, rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: launchType))
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    // MARK: - User Launch

    /// User launch in `UISceneDelegate`-based app.
    private var userLaunchWithSceneDelegate: AppRunner.ProcessLaunchType { .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate) }
    /// User launch in `UIApplicationDelegate`-based app.
    private var userLaunchWithAppDelegate: AppRunner.ProcessLaunchType { .userLaunchInAppDelegateBasedApp(processLaunchDate: processLaunchDate) }

    func testGivenUserLaunch_whenNoEventIsTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let session = try when.then().takeSingle()
            XCTAssertNotNil(session.applicationStartAction)
            DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
            DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
            DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let session = try when.then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
            DDAssertEqual(session.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
        }
    }

    func testGivenUserLaunch_whenManualViewIsTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, manualViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, manualViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenUserLaunch_whenAutomaticViewIsTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, automaticViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            },
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, automaticViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenUserLaunch_whenActionsAreTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }
    }

    func testGivenUserLaunch_whenResourceIsTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenUserLaunch_whenLongTasksAreTracked() throws {
        // Given
        let givens1 = [
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMBeforeAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens1 {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNotNil(session.applicationStartAction)
                DDAssertEqual(session.applicationStartupTime, timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.sessionStartDate, processLaunchDate, accuracy: accuracy)
                DDAssertEqual(session.duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, timeToSDKInit + timeToAppBecomeActive + dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 2)
            }
        }

        // Given
        let givens2 = [
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithSceneDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            },
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate),
            enableRUMAfterAppBecomesActive(userLaunchWithAppDelegate) { rumConfig in
                rumConfig.trackBackgroundEvents = true
            }
        ]

        for given in givens2 {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 2)
            }
        }
    }

    // MARK: - OS Prewarm Launch

    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate) }

    func testGivenOSPrewarmLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch)
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let session = try when.then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
            DDAssertEqual(session.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
        }
    }

    func testGivenOSPrewarmLaunch_whenManualViewIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, manualViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch)
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, manualViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenAutomaticViewIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, automaticViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, automaticViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenActionsAreTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch)
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenResourceIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch)
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenOSPrewarmLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .prewarm)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 2)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(osPrewarmLaunch)
        let given4 = enableRUMAfterAppBecomesActive(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
            }
        }
    }

    // MARK: - Background Launch

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch)
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when = given.when(.appEntersBackground(after: dt1))

            // When
            let session = try when.then().takeSingle()
            XCTAssertNil(session.applicationStartAction)
            XCTAssertNil(session.applicationStartupTime)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
            DDAssertEqual(session.duration, dt1, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
            DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
        }
    }

    func testGivenBackgroundLaunch_whenManualViewIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, manualViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch)
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.stopManualView(after: dt2))
            let when2 = given
                .when(.startManualView(after: dt1, viewName: manualViewName))
                .and(.appEntersBackground(after: dt2))
                .and(.stopManualView(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, manualViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenBackgroundLaunch_whenAutomaticViewIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, automaticViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.stopAutomaticView(after: dt2, viewController: automaticView))
            let when2 = given
                .when(.startAutomaticView(after: dt1, viewController: automaticView))
                .and(.appEntersBackground(after: dt2))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 2)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1, accuracy: accuracy)
                XCTAssertEqual(session.views[1].name, automaticViewName)
                DDAssertEqual(session.views[1].duration, dt2, accuracy: accuracy)
            }
        }
    }

    func testGivenBackgroundLaunch_whenActionsAreTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch)
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoActions(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction1" }))
                XCTAssertNotNil(session.views[0].actionEvents.first(where: { $0.action.target?.name == "CustomAction2" }))
            }
        }
    }

    func testGivenBackgroundLaunch_whenResourceIsTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch)
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackResource(after: dt1, duration: dt2))
            let when2 = given
                .when(.trackResource(after: dt1, duration: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertNotNil(session.views[0].resourceEvents.first(where: { $0.resource.url == "https://resource.url" }))
            }
        }
    }

    func testGivenBackgroundLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = enableRUMBeforeAppBecomesActive(backgroundLaunch)
        let given2 = enableRUMBeforeAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartupTime)
                XCTAssertNil(session.applicationStartAction)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + timeToAppBecomeActive + dt1, accuracy: accuracy)
                DDAssertEqual(session.duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
                XCTAssertEqual(session.views[0].viewEvents.last?.view.longTask?.count, 2)
            }
        }

        // Given
        let given3 = enableRUMAfterAppBecomesActive(backgroundLaunch)
        let given4 = enableRUMAfterAppBecomesActive(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given3, given4] {
            // When
            let when1 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
            let when2 = given
                .when(.trackTwoLongTasks(after1: dt1, after2: dt2))
                .and(.appEntersBackground(after: 0))

            for when in [when1, when2] {
                // Then
                let session = try when.then().takeSingle()
                XCTAssertNil(session.applicationStartAction)
                XCTAssertNil(session.applicationStartupTime)
                DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToAppBecomeActive + timeToSDKInit, accuracy: accuracy)
                DDAssertEqual(session.duration, dt1 + dt2, accuracy: accuracy)
                XCTAssertEqual(session.sessionPrecondition, .userAppLaunch)
                XCTAssertEqual(session.views.count, 1)
                XCTAssertEqual(session.views[0].name, applicationLaunchViewName)
                DDAssertEqual(session.views[0].duration, dt1 + dt2, accuracy: accuracy)
            }
        }
    }
}
