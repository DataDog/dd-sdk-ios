/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggerBuilderTests: XCTestCase {
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()

    override func setUp() {
        super.setUp()
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directory: temporaryDirectory,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.2.3",
                    applicationBundleIdentifier: "com.datadog.unit-tests",
                    serviceName: "service-name",
                    environment: "tests"
                )
            ),
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider
            )
        )
    }

    override func tearDown() {
        LoggingFeature.instance = nil
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.builder.build()

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        let feature = LoggingFeature.instance!
        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "com.datadog.unit-tests")
        XCTAssertTrue(logBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNil(logBuilder.carrierInfoProvider)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        let logger1 = Logger.builder.build()
        XCTAssertNotNil(logger1.rumContextIntegration)

        let logger2 = Logger.builder.bundleWithRUM(false).build()
        XCTAssertNil(logger2.rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        let logger1 = Logger.builder.build()
        XCTAssertNotNil(logger1.activeSpanIntegration)

        let logger2 = Logger.builder.bundleWithTrace(false).build()
        XCTAssertNil(logger2.activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .bundleWithRUM(false)
            .bundleWithTrace(false)
            .build()

        XCTAssertNil(logger.rumContextIntegration)
        XCTAssertNil(logger.activeSpanIntegration)

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        let feature = LoggingFeature.instance!
        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "custom-logger-name")
        XCTAssertTrue(logBuilder.userInfoProvider === feature.userInfoProvider)
        XCTAssertTrue(logBuilder.networkConnectionInfoProvider as AnyObject === feature.networkConnectionInfoProvider as AnyObject)
        XCTAssertTrue(logBuilder.carrierInfoProvider as AnyObject === feature.carrierInfoProvider as AnyObject)
    }

    func testUsingDifferentOutputs() throws {
        assertThat(
            logger: Logger.builder.build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).build(),
            usesOutput: NoOpLogOutput.self
        )
        assertThat(
            logger: Logger.builder.printLogsToConsole(true).build(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: Logger.builder.printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(),
            usesOutput: LogConsoleOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(),
            usesOutput: NoOpLogOutput.self
        )
    }
}

// MARK: - Helpers

private func assertThat(logger: Logger, usesOutput outputType: LogOutput.Type, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(type(of: logger.logOutput) == outputType, file: file, line: line)
}

private func assertThat(logger: Logger, usesCombinedOutputs outputTypes: [LogOutput.Type], file: StaticString = #file, line: UInt = #line) {
    if let combinedOutputs = (logger.logOutput as? CombinedLogOutput)?.combinedOutputs {
        XCTAssertEqual(outputTypes.count, combinedOutputs.count, file: file, line: line)
        outputTypes.forEach { outputType in
            XCTAssertTrue(combinedOutputs.contains { type(of: $0) == outputType }, file: file, line: line)
        }
    } else {
        XCTFail(file: file, line: line)
    }
}
