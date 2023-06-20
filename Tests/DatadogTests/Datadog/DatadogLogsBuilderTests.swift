/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogLogs
@testable import Datadog

class DatadogLogsBuilderTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockRandom())

        let feature: LogsFeature = .mockWith(
            applicationBundleIdentifier: "com.datadog.unit-tests"
        )
        try! core.register(feature: feature)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = DatadogLogger.builder.build(in: core)

        let remoteLogger = try XCTUnwrap(logger.logger as? RemoteLogger)
        XCTAssertNil(remoteLogger.configuration.service)
        XCTAssertEqual(remoteLogger.configuration.loggerName, "com.datadog.unit-tests")
        XCTAssertFalse(remoteLogger.configuration.sendNetworkInfo)
        XCTAssertEqual(remoteLogger.configuration.threshold, .debug)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertTrue(remoteLogger.rumContextIntegration)
        XCTAssertTrue(remoteLogger.activeSpanIntegration)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let logger1 = DatadogLogger.builder.build(in: core)
        XCTAssertNotNil((logger1.logger as? RemoteLogger)?.rumContextIntegration)

        let logger2 = DatadogLogger.builder.bundleWithRUM(false).build()
        XCTAssertNil((logger2.logger as? RemoteLogger)?.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let logger1 = DatadogLogger.builder.build(in: core)
        XCTAssertTrue(try XCTUnwrap(logger1.logger as? RemoteLogger).activeSpanIntegration)

        let logger2 = DatadogLogger.builder.bundleWithTrace(false).build(in: core)
        XCTAssertFalse(try XCTUnwrap(logger2.logger as? RemoteLogger).activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        let logger = DatadogLogger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .bundleWithRUM(false)
            .bundleWithTrace(false)
            .set(datadogReportingThreshold: .error)
            .build(in: core)

        let remoteLogger = try XCTUnwrap(logger.logger as? RemoteLogger)
        XCTAssertEqual(remoteLogger.configuration.service, "custom-service-name")
        XCTAssertEqual(remoteLogger.configuration.loggerName, "custom-logger-name")
        XCTAssertTrue(remoteLogger.configuration.sendNetworkInfo)
        XCTAssertEqual(remoteLogger.configuration.threshold, .error)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertFalse(remoteLogger.rumContextIntegration)
        XCTAssertFalse(remoteLogger.activeSpanIntegration)
    }

    func testCombiningInternalLoggers() throws {
        var logger: DatadogLogger

        logger = DatadogLogger.builder.build(in: core)
        XCTAssertTrue(logger.logger is RemoteLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(true).build(in: core)
        XCTAssertTrue(logger.logger is RemoteLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(false).build(in: core)
        XCTAssertTrue(logger.logger is NOPLogger)

        logger = DatadogLogger.builder.printLogsToConsole(true).build(in: core)
        var combinedLogger = try XCTUnwrap(logger.logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = DatadogLogger.builder.printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.logger is RemoteLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(in: core)
        combinedLogger = try XCTUnwrap(logger.logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(in: core)
        XCTAssertTrue(logger.logger is ConsoleLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.logger is RemoteLogger)

        logger = DatadogLogger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.logger is NOPLogger)
    }
}
