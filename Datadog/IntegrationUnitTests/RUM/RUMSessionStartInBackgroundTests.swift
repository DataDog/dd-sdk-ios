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

class RUMSessionStartInBackgroundTests: RUMSessionTestsBase {
    // MARK: - Scenarios for enabling RUM in background

    private func enableRUM(_ launchType: AppRunner.ProcessLaunchType, rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: launchType))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    // MARK: - OS Prewarm Launch

    private var osPrewarmLaunch: AppRunner.ProcessLaunchType { .osPrewarm(processLaunchDate: processLaunchDate, runtimeLoadDate: runtimeLoadDate) }

    func testGivenOSPrewarmLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = enableRUM(osPrewarmLaunch)
        let given2 = enableRUM(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given

            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    func testGivenOSPrewarmLaunch_whenEventAreTracked() throws {
        // Given
        // - BET disabled
        let given1 = enableRUM(osPrewarmLaunch)

        // When
        let when1 = given1.when(.trackTwoActions(after1: dt1, after2: dt2))
        let when2 = given1.when(.trackResource(after: dt1, duration: dt2))

        for when in [when1, when2] {
            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        // - BET enabled
        let given2 = enableRUM(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        // When
        let when3 = given2.when(.trackTwoActions(after1: dt1, after2: dt2))
        let when4 = given2.when(.trackResource(after: dt1, duration: dt2))

        for when in [when3, when4] {
            // Then
            let session = try when.then().takeSingle()
            XCTAssertNil(session.ttidEvent)
            XCTAssertNil(session.timeToInitialDisplay)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
            DDAssertEqual(session.duration, dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .prewarm)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, backgroundViewName)
            DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
        }
    }

    func testGivenOSPrewarmLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = enableRUM(osPrewarmLaunch)
        let given2 = enableRUM(osPrewarmLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given.when(.trackTwoLongTasks(after1: dt1, after2: dt2))

            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    // MARK: - Background Launch

    private var backgroundLaunch: AppRunner.ProcessLaunchType { .backgroundLaunch(processLaunchDate: processLaunchDate) }

    func testGivenBackgroundLaunch_whenNoEventIsTracked() throws {
        // Given
        let given1 = enableRUM(backgroundLaunch)
        let given2 = enableRUM(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given

            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    func testGivenBackgroundLaunch_whenEventAreTracked() throws {
        // Given
        // - BET disabled
        let given1 = enableRUM(backgroundLaunch)

        // When
        let when1 = given1.when(.trackTwoActions(after1: dt1, after2: dt2))
        let when2 = given1.when(.trackResource(after: dt1, duration: dt2))

        for when in [when1, when2] {
            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }

        // Given
        // - BET enabled
        let given2 = enableRUM(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        // When
        let when3 = given2.when(.trackTwoActions(after1: dt1, after2: dt2))
        let when4 = given2.when(.trackResource(after: dt1, duration: dt2))

        for when in [when3, when4] {
            let session = try when.then().takeSingle()
            XCTAssertNil(session.ttidEvent)
            XCTAssertNil(session.timeToInitialDisplay)
            DDAssertEqual(session.sessionStartDate, processLaunchDate + timeToSDKInit + dt1, accuracy: accuracy)
            DDAssertEqual(session.duration, dt2, accuracy: accuracy)
            XCTAssertEqual(session.sessionPrecondition, .backgroundLaunch)
            XCTAssertEqual(session.views.count, 1)
            XCTAssertEqual(session.views[0].name, backgroundViewName)
            DDAssertEqual(session.views[0].duration, dt2, accuracy: accuracy)
        }
    }

    func testGivenBackgroundLaunch_whenLongTasksAreTracked() throws {
        // Given
        let given1 = enableRUM(backgroundLaunch)
        let given2 = enableRUM(backgroundLaunch) { rumConfig in
            rumConfig.trackBackgroundEvents = true
        }

        for given in [given1, given2] {
            // When
            let when = given.when(.trackTwoLongTasks(after1: dt1, after2: dt2))

            // Then
            let sessions = try when.then()
            XCTAssertTrue(sessions.isEmpty)
        }
    }
}
