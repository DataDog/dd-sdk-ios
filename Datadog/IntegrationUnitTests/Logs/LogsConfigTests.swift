/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogLogs

/// Tests covering Logs setup, enablement, and `Logger.Configuration` options.
///
/// See `Datadog/IntegrationUnitTests/Logs/SCENARIOS.md` for the full list of scenarios this file covers.
class LogsConfigTests: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    private let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()`).
    private let timeToSDKInit: TimeInterval = 0.7

    // MARK: - §1 Setup & enablement

    /// Logs feature enable after SDK init — `Logs.enable(in: app.core)` after `Datadog.initialize(...)`
    /// registers the feature; subsequent `Logger.create(in: app.core)` produces a working remote logger.
    func testGivenSDKInitialized_whenLogsEnabledAfterInit_loggerProducesRecordedLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("after enable")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded after enable + emit")
        result.logs[0].assertStatus(equals: "info")
        result.logs[0].assertMessage(equals: "after enable")
    }

    /// Logger creation before Logs feature enabled — `Logger.create` returns a `NOPLogger`
    /// (no logs recorded) when `Logs.enable` was never called.
    func testGivenLogsFeatureNotEnabled_whenLoggerIsCreated_itProducesNoRecordedLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                // Note: Logs.enable(in:) is intentionally NOT called.
                app.logger = Logger.create(in: app.core)
                app.logger.info("hello")
                app.logger.warn("warn")
                app.logger.error("err")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 0, "No logs should be recorded when Logs feature was never enabled")
    }

    /// Logs feature enabled twice — second `Logs.enable(in: app.core)` is a no-op;
    /// previously-created loggers continue working.
    func testGivenLogsFeatureEnabled_whenEnabledASecondTime_previouslyCreatedLoggerStillWorks() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("before second enable")
            }
            .and { app in
                // Re-enable Logs on the same core — expected to be a no-op.
                Logs.enable(in: app.core)
            }
            .when { app in
                // Reuse the SAME logger created before the second enable.
                app.logger.info("after second enable")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Both logs should be recorded; second enable must not break the existing logger")

        let messages: [String] = try result.logs.map { try $0.value(forKeyPath: "message") }
        XCTAssertTrue(messages.contains("before second enable"), "Log emitted before the second enable should still be recorded")
        XCTAssertTrue(messages.contains("after second enable"), "Log emitted after the second enable should be recorded by the previously-created logger")

        for log in result.logs {
            log.assertStatus(equals: "info")
        }
    }
}
