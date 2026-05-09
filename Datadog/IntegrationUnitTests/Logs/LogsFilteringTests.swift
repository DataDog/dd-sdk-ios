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

    func testGivenLoggerWithWarnThresholdAndConsoleOutput_whenLogsAreEmittedAtEachLevel_consoleReceivesAllSixWhileOnlyWarnAndAboveAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteLogThreshold = .warn
                config.consoleLogFormat = .short
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
        XCTAssertEqual(result.logs.count, 3, "Only warn/error/critical should reach the remote pipeline")
        XCTAssertEqual(
            result.consoleOutput.count,
            6,
            "Console output should receive every emitted log regardless of remoteLogThreshold"
        )
    }

    // MARK: - §9 Console output

    func testGivenLoggerWithShortConsoleFormat_whenInfoLogIsEmitted_consoleMessageContainsLevelAndMessage() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.consoleLogFormat = .short
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("test")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.consoleOutput.count, 1, "Exactly one console message should be printed")
        let line = result.consoleOutput[0]
        XCTAssertTrue(line.contains("[INFO]"), "Short format should include the level marker; got: \(line)")
        XCTAssertTrue(line.contains("test"), "Short format should include the message; got: \(line)")
        XCTAssertFalse(line.hasPrefix(" "), "Short format has no prefix, so the line should not start with whitespace; got: \(line)")
    }

    func testGivenLoggerWithShortWithPrefixConsoleFormat_whenLogIsEmitted_consoleMessageStartsWithPrefix() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.consoleLogFormat = .shortWith(prefix: "MyApp")
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("test")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.consoleOutput.count, 1, "Exactly one console message should be printed")
        let line = result.consoleOutput[0]
        XCTAssertTrue(line.hasPrefix("MyApp "), "shortWith(prefix:) should prepend the prefix followed by a space; got: \(line)")
        XCTAssertTrue(line.contains("[INFO]"))
        XCTAssertTrue(line.contains("test"))
    }

    func testGivenLoggerWithShortConsoleFormat_whenErrorLogIsEmittedWithSwiftError_consoleMessageContainsErrorBlock() throws {
        struct LoginFailed: Error, CustomStringConvertible {
            var description: String { "credentials rejected" }
        }

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.consoleLogFormat = .short
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.error("oops", error: LoginFailed())
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.consoleOutput.count, 1, "Exactly one console message should be printed")
        let line = result.consoleOutput[0]
        XCTAssertTrue(line.contains("[ERROR]"))
        XCTAssertTrue(line.contains("oops"))
        XCTAssertTrue(line.contains("Error details:"), "Error log on console should include the error block; got: \(line)")
        XCTAssertTrue(line.contains("LoginFailed"), "Error block should include the error type name (error.kind); got: \(line)")
        XCTAssertTrue(line.contains("credentials rejected"), "Error block should include the error description (error.message); got: \(line)")
    }

    func testGivenLoggerWithConsoleOutputZeroSampleRateAndCriticalThreshold_whenLogsAreEmitted_consoleReceivesAllAndNoLogsAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteSampleRate = 0
                config.remoteLogThreshold = .critical
                config.consoleLogFormat = .short
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("info-msg")
                app.logger.warn("warn-msg")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 0, "Both remote filters should drop everything from the remote pipeline")
        XCTAssertEqual(result.consoleOutput.count, 2, "Console output ignores remoteSampleRate and remoteLogThreshold")
        XCTAssertTrue(result.consoleOutput[0].contains("info-msg"))
        XCTAssertTrue(result.consoleOutput[1].contains("warn-msg"))
    }

    // MARK: - §10 Event mapper

    func testGivenLogsConfigurationWithMessageMapper_whenLogIsEmitted_recordedMessageIsMapped() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                var config = Logs.Configuration()
                config.eventMapper = { event in
                    var mapped = event
                    mapped.message = "MAPPED: \(event.message)"
                    return mapped
                }
                Logs.enable(with: config, in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("hello")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let message: String = try result.logs[0].value(forKeyPath: "message")
        XCTAssertEqual(message, "MAPPED: hello", "Recorded log should carry the message produced by the mapper")
    }

    func testGivenLogsConfigurationWithAttributesMapper_whenLogIsEmitted_recordedAttributesReflectMapperChanges() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                var config = Logs.Configuration()
                config.eventMapper = { event in
                    var mapped = event
                    mapped.attributes.userAttributes["original-key"] = "mapped-value"
                    mapped.attributes.userAttributes["mapper-added"] = true
                    return mapped
                }
                Logs.enable(with: config, in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("with-attrs", attributes: ["original-key": "original-value"])
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let original: String = try result.logs[0].value(forKeyPath: "original-key")
        let added: Bool = try result.logs[0].value(forKeyPath: "mapper-added")
        XCTAssertEqual(original, "mapped-value", "Mapper should overwrite the existing user attribute")
        XCTAssertTrue(added, "Mapper should be able to add a new user attribute")
    }

    func testGivenLogsConfigurationWithMapperReturningNil_whenLogsAreEmitted_noLogsAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                var config = Logs.Configuration()
                config.eventMapper = { _ in nil }
                Logs.enable(with: config, in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("dropped-1")
                app.logger.warn("dropped-2")
                app.logger.error("dropped-3")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 0, "Mapper returning nil should drop every emitted log")
    }

    func testGivenLogsConfigurationWithIdentityMapper_whenLogIsEmitted_recordedPayloadMatchesBaseline() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK(sdkSetup: { config in
                config.service = "harness-service"
            }))
            .when { app in
                var config = Logs.Configuration()
                config.eventMapper = { $0 }
                Logs.enable(with: config, in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("identity")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]
        let message: String = try log.value(forKeyPath: "message")
        let service: String = try log.value(forKeyPath: "service")
        XCTAssertEqual(message, "identity", "Identity mapper should not modify the message")
        log.assertStatus(equals: "info")
        XCTAssertEqual(service, "harness-service", "Identity mapper should not modify the service")
    }

    func testGivenLogsConfigurationMapper_whenMultipleLoggersEmit_mapperAppliesToAll() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                var config = Logs.Configuration()
                config.eventMapper = { event in
                    var mapped = event
                    mapped.message = "PFX:\(event.message)"
                    return mapped
                }
                Logs.enable(with: config, in: app.core)
                app.loggers["a"] = Logger.create(with: Logger.Configuration(name: "logger-a"), in: app.core)
                app.loggers["b"] = Logger.create(with: Logger.Configuration(name: "logger-b"), in: app.core)
                app.loggers["a"]?.info("from-a")
                app.loggers["b"]?.info("from-b")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded — one per logger")
        let messages = Set(try result.logs.map { try $0.value(forKeyPath: "message") as String })
        XCTAssertEqual(messages, ["PFX:from-a", "PFX:from-b"], "Mapper should apply to logs from every logger")
    }
}
