/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggerBuilderTests: XCTestCase {
    private let userInfoProvider: UserInfoProvider = .mockAny()
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()
    private lazy var core = DatadogCoreMock(
        context: .mockWith(
            service: "service-name",
            env: "tests",
            version: "1.2.3",
            applicationBundleIdentifier: "com.datadog.unit-tests",
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            userInfoProvider: userInfoProvider
        )
    )

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
        let feature: LoggingFeature = .mockNoOp()
        core.register(feature: feature)
    }

    override func tearDown() {
        core.flush()
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.builder.build(in: core)

        let remoteLogger = try XCTUnwrap(logger.v2Logger as? RemoteLogger)
        XCTAssertEqual(remoteLogger.configuration.service, "service-name")
        XCTAssertEqual(remoteLogger.configuration.loggerName, "com.datadog.unit-tests")
        XCTAssertFalse(remoteLogger.configuration.sendNetworkInfo)
        XCTAssertEqual(remoteLogger.configuration.threshold, .debug)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertNil(remoteLogger.rumContextIntegration)
        XCTAssertNil(remoteLogger.rumErrorsIntegration)
        XCTAssertNil(remoteLogger.activeSpanIntegration)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil((logger1.v2Logger as? RemoteLogger)?.rumContextIntegration)

        let logger2 = Logger.builder.bundleWithRUM(false).build()
        XCTAssertNil((logger2.v2Logger as? RemoteLogger)?.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil((logger1.v2Logger as? RemoteLogger)?.activeSpanIntegration)

        let logger2 = Logger.builder.bundleWithTrace(false).build(in: core)
        XCTAssertNil((logger2.v2Logger as? RemoteLogger)?.activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let tracing: TracingFeature = .mockNoOp()
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
        XCTAssertNil(remoteLogger.rumContextIntegration)
        XCTAssertNotNil(remoteLogger.rumErrorsIntegration, "When RUM is enabled, `rumErrorsIntegration` should be available")
        XCTAssertNil(remoteLogger.activeSpanIntegration)
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
