/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggerBuilderTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockRandom())

        let feature: LoggingFeature = .mockWith(
            configuration: .mockWith(applicationBundleIdentifier: "com.datadog.unit-tests")
        )
        core.register(feature: feature)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.builder.build(in: core)

        let remoteLogger = try XCTUnwrap(logger.v2Logger as? RemoteLogger)
        XCTAssertNil(remoteLogger.configuration.service)
        XCTAssertEqual(remoteLogger.configuration.loggerName, "com.datadog.unit-tests")
        XCTAssertFalse(remoteLogger.configuration.sendNetworkInfo)
        XCTAssertEqual(remoteLogger.configuration.threshold, .debug)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertTrue(remoteLogger.rumContextIntegration)
        XCTAssertTrue(remoteLogger.activeSpanIntegration)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil((logger1.v2Logger as? RemoteLogger)?.rumContextIntegration)

        let logger2 = Logger.builder.bundleWithRUM(false).build()
        XCTAssertNil((logger2.v2Logger as? RemoteLogger)?.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertTrue(try XCTUnwrap(logger1.v2Logger as? RemoteLogger).activeSpanIntegration)

        let logger2 = Logger.builder.bundleWithTrace(false).build(in: core)
        XCTAssertFalse(try XCTUnwrap(logger2.v2Logger as? RemoteLogger).activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .bundleWithRUM(false)
            .bundleWithTrace(false)
            .set(datadogReportingThreshold: .error)
            .build(in: core)

        let remoteLogger = try XCTUnwrap(logger.v2Logger as? RemoteLogger)
        XCTAssertEqual(remoteLogger.configuration.service, "custom-service-name")
        XCTAssertEqual(remoteLogger.configuration.loggerName, "custom-logger-name")
        XCTAssertTrue(remoteLogger.configuration.sendNetworkInfo)
        XCTAssertEqual(remoteLogger.configuration.threshold, .error)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertFalse(remoteLogger.rumContextIntegration)
        XCTAssertFalse(remoteLogger.activeSpanIntegration)
    }

    func testCombiningInternalLoggers() throws {
        var logger: Logger

        logger = Logger.builder.build(in: core)
        XCTAssertTrue(logger.v2Logger is RemoteLogger)

        logger = Logger.builder.sendLogsToDatadog(true).build(in: core)
        XCTAssertTrue(logger.v2Logger is RemoteLogger)

        logger = Logger.builder.sendLogsToDatadog(false).build(in: core)
        XCTAssertTrue(logger.v2Logger is NOPLogger)

        logger = Logger.builder.printLogsToConsole(true).build(in: core)
        var combinedLogger = try XCTUnwrap(logger.v2Logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = Logger.builder.printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.v2Logger is RemoteLogger)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(in: core)
        combinedLogger = try XCTUnwrap(logger.v2Logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(in: core)
        XCTAssertTrue(logger.v2Logger is ConsoleLogger)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.v2Logger is RemoteLogger)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.v2Logger is NOPLogger)
    }
}
