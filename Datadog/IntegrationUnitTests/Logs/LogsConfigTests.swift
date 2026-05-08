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

    // MARK: - §2 Logger creation & configuration

    /// Default Logger.Configuration — log emitted from a logger created with `Logger.Configuration()`
    /// carries the default `service` (from SDK env-derived service name) and `logger.name` (from main bundle id),
    /// and contains no `network.client.*` attributes (since `networkInfoEnabled=false` by default).
    func testGivenDefaultLoggerConfiguration_whenLogIsEmitted_itHasDefaultServiceAndLoggerName() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(with: Logger.Configuration(), in: app.core)
                app.logger.info("default-config log")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")

        let service: String = try result.logs[0].value(forKeyPath: "service")
        let loggerName: String = try result.logs[0].value(forKeyPath: "logger.name")

        XCTAssertFalse(service.isEmpty, "Default service should fall back to a non-empty value (bundle id)")
        XCTAssertFalse(loggerName.isEmpty, "Default logger.name should fall back to a non-empty value (bundle id)")
        XCTAssertEqual(
            service,
            loggerName,
            "Both default service and default logger.name fall back to the application bundle identifier, so they must match"
        )

        // networkInfoEnabled defaults to false → no network.client.* attributes.
        result.logs[0].assertNoValue(forKeyPath: "network.client.reachability")
    }

    /// Logger.Configuration.service overrides default — explicit `service: "checkout"`
    /// appears in the recorded log's `service` field instead of the default bundle id.
    func testGivenLoggerConfigurationWithExplicitService_whenLogIsEmitted_itUsesProvidedServiceName() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.service = "checkout"
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("custom-service log")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertService(equals: "checkout")
    }

    /// Logger.Configuration.name overrides default — explicit `name: "auth-logger"`
    /// appears in `logger.name` instead of the default bundle id.
    func testGivenLoggerConfigurationWithExplicitName_whenLogIsEmitted_itUsesProvidedLoggerName() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.name = "auth-logger"
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("custom-name log")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertLoggerName(equals: "auth-logger")
    }

    /// Multiple named loggers — independent tag state. A tag added on logger A
    /// is not visible on logs emitted by logger B.
    func testGivenTwoLoggers_whenTagIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.loggers["a"] = Logger.create(with: Logger.Configuration(name: "logger-a"), in: app.core)
                app.loggers["b"] = Logger.create(with: Logger.Configuration(name: "logger-b"), in: app.core)
            }
            .when { app in
                app.loggers["a"]?.addTag(withKey: "feature", value: "promo")
                app.loggers["a"]?.info("from a")
                app.loggers["b"]?.info("from b")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Exactly two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "logger-a" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "logger-b" })

        let tagsA: String = try logA.value(forKeyPath: "ddtags")
        let tagsB: String = try logB.value(forKeyPath: "ddtags")

        XCTAssertTrue(tagsA.contains("feature:promo"), "Logger A's log should carry its own tag")
        XCTAssertFalse(tagsB.contains("feature:promo"), "Logger B's log must not carry tags added on logger A")
    }

    /// Multiple named loggers — independent attribute state. An attribute added on logger A
    /// is not visible on logs emitted by logger B.
    func testGivenTwoLoggers_whenAttributeIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.loggers["a"] = Logger.create(with: Logger.Configuration(name: "logger-a"), in: app.core)
                app.loggers["b"] = Logger.create(with: Logger.Configuration(name: "logger-b"), in: app.core)
            }
            .when { app in
                app.loggers["a"]?.addAttribute(forKey: "tenant", value: "acme")
                app.loggers["a"]?.info("from a")
                app.loggers["b"]?.info("from b")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Exactly two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "logger-a" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "logger-b" })

        let tenantOnA: String? = try logA.valueOrNil(forKeyPath: "tenant")
        let tenantOnB: String? = try logB.valueOrNil(forKeyPath: "tenant")

        XCTAssertEqual(tenantOnA, "acme", "Logger A's log should carry its own attribute")
        XCTAssertNil(tenantOnB, "Logger B's log must not carry attributes added on logger A")
    }

    /// Logger with `remoteSampleRate=0` and no console — `Logger.create` returns a NOPLogger;
    /// emitting any logs through it produces zero recorded logs.
    func testGivenLoggerWithZeroRemoteSampleRateAndNoConsole_whenLogsAreEmitted_noLogsAreRecorded() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.remoteSampleRate = 0
                config.consoleLogFormat = nil
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("dropped")
                app.logger.warn("dropped")
                app.logger.error("dropped")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 0, "NOPLogger from `remoteSampleRate=0` + no console must record nothing")
    }

    /// `loggerVersion` populated from SDK version — every log carries the current
    /// `__sdkVersion` (from `DatadogCore/Sources/Versioning.swift`) in `logger.version`.
    func testGivenAnyLogger_whenLogIsEmitted_itCarriesCurrentSDKVersionInLoggerVersion() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("version-check")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertValue(forKeyPath: "logger.version", equals: __sdkVersion)
    }
}
