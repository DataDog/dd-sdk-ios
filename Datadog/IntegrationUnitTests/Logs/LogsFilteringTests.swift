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

/// Tests covering what gets dropped or transformed before recording: sampling, threshold,
/// console, event mapper.
///
/// See `Datadog/IntegrationUnitTests/Logs/SCENARIOS.md` for the full list of scenarios this file covers.
class LogsFilteringTests: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    private let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()`).
    private let timeToSDKInit: TimeInterval = 0.7

    // MARK: - §7 Sampling (remoteSampleRate)

    func testGivenLoggerWithZeroRemoteSampleRateAndConsoleOutput_whenLogsAreEmitted_noLogsAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteSampleRate = 0
                config.consoleLogFormat = .short
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.debug("d")
                app.logger.info("i")
                app.logger.notice("n")
                app.logger.warn("w")
                app.logger.error("e")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(
            result.logs.count,
            0,
            "remoteSampleRate=0 should drop all logs from the remote pipeline; ConsoleLogger keeps the logger alive but does not emit to recordedLogs()"
        )
    }

    func testGivenLoggerWithMaxRemoteSampleRate_whenLogsAreEmitted_allLogsAreRecorded() throws {
        let messages = ["one", "two", "three", "four", "five"]

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteSampleRate = 100
                app.logger = Logger.create(with: config, in: app.core)
                for message in messages {
                    app.logger.info(message)
                }
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, messages.count, "remoteSampleRate=100 should keep every emitted log")
        let recordedMessages = try result.logs.map { try $0.value(forKeyPath: "message") as String }
        XCTAssertEqual(recordedMessages, messages, "Every emitted message should appear in recordedLogs() in order")
    }

    // MARK: - §8 Log threshold (remoteLogThreshold)

    func testGivenLoggerWithWarnThreshold_whenLogsAreEmittedAtEachLevel_onlyWarnAndAboveAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteLogThreshold = .warn
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.debug("d")
                app.logger.info("i")
                app.logger.notice("n")
                app.logger.warn("w")
                app.logger.error("e")
                app.logger.critical("c")
            }

        // Then
        let result = try when.then()
        let expectedStatuses = ["warn", "error", "critical"]
        XCTAssertEqual(result.logs.count, expectedStatuses.count, "Only logs at or above .warn should be recorded")
        for (index, expectedStatus) in expectedStatuses.enumerated() {
            result.logs[index].assertStatus(equals: expectedStatus)
        }
    }

    func testGivenLoggerWithCriticalThreshold_whenLogsAreEmittedAtEachLevel_onlyCriticalIsRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteLogThreshold = .critical
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.debug("d")
                app.logger.info("i")
                app.logger.notice("n")
                app.logger.warn("w")
                app.logger.error("e")
                app.logger.critical("c")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Only the critical log should be recorded")
        result.logs[0].assertStatus(equals: "critical")
    }

    func testGivenLoggerWithDefaultThreshold_whenLogsAreEmittedAtEachLevel_allLevelsAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(with: Logger.Configuration(), in: app.core)
                app.logger.debug("d")
                app.logger.info("i")
                app.logger.notice("n")
                app.logger.warn("w")
                app.logger.error("e")
                app.logger.critical("c")
            }

        // Then
        let result = try when.then()
        let expectedStatuses = ["debug", "info", "notice", "warn", "error", "critical"]
        XCTAssertEqual(result.logs.count, expectedStatuses.count, "Default threshold (.debug) should accept every level")
        for (index, expectedStatus) in expectedStatuses.enumerated() {
            result.logs[index].assertStatus(equals: expectedStatus)
        }
    }
}
