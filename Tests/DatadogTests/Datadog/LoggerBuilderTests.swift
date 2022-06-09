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
            configuration: .mockWith(
                applicationVersion: "1.2.3",
                applicationBundleIdentifier: "com.datadog.unit-tests",
                serviceName: "service-name",
                environment: "tests"
            ),
            dependencies: .mockWith(
                userInfoProvider: userInfoProvider,
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
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

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertFalse(logger.sendNetworkInfo)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)
        XCTAssertNil(logger.logEventMapper)
        XCTAssertNil(logger.serviceName, "service-name")
        XCTAssertNil(logger.loggerName, "com.datadog.unit-tests")
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil(logger1.rumContextIntegration)

        let logger2 = Logger.builder.bundleWithRUM(false).build()
        XCTAssertNil(logger2.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        let logger1 = Logger.builder.build(in: core)
        XCTAssertNotNil(logger1.activeSpanIntegration)

        let logger2 = Logger.builder.bundleWithTrace(false).build(in: core)
        XCTAssertNil(logger2.activeSpanIntegration)
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
            .build(in: core)

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertTrue(logger.sendNetworkInfo)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)
        XCTAssertNil(logger.logEventMapper)
        XCTAssertEqual(logger.serviceName, "custom-service-name")
        XCTAssertEqual(logger.loggerName, "custom-logger-name")
    }

    func testUsingDifferentOutputs() throws {
        var logger: Logger

        logger = Logger.builder.build(in: core)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.sendLogsToDatadog(true).build(in: core)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.sendLogsToDatadog(false).build(in: core)
        XCTAssertFalse(logger.useCoreOutput)
        XCTAssertNil(logger.additionalOutput)

        logger = Logger.builder.printLogsToConsole(true).build(in: core)
        var combinedOutputs = try XCTUnwrap(logger.additionalOutput as? CombinedLogOutput).combinedOutputs
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertEqual(combinedOutputs.count, 2)
        XCTAssertTrue(combinedOutputs[0] is LogConsoleOutput)
        XCTAssertTrue(combinedOutputs[1] is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(in: core)
        combinedOutputs = try XCTUnwrap(logger.additionalOutput as? CombinedLogOutput).combinedOutputs
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertEqual(combinedOutputs.count, 2)
        XCTAssertTrue(combinedOutputs[0] is LogConsoleOutput)
        XCTAssertTrue(combinedOutputs[1] is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(in: core)
        XCTAssertFalse(logger.useCoreOutput)
        XCTAssertTrue(logger.additionalOutput is LogConsoleOutput)

        logger = Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(in: core)
        XCTAssertTrue(logger.useCoreOutput)
        XCTAssertTrue(logger.additionalOutput is LoggingWithRUMErrorsIntegration)

        logger = Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(in: core)
        XCTAssertFalse(logger.useCoreOutput)
        XCTAssertNil(logger.additionalOutput)
    }
}
