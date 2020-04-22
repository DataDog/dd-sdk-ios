/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog
@testable import DatadogObjc

class DDLoggerBuilderTests: XCTestCase {
    private let appContext: AppContext = .mockWith(bundleIdentifier: "com.datadog.sdk-unit-tests")
    private let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()
    private let carrierInfoProvider: CarrierInfoProviderMock = .mockAny()

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Default logger

    func testBuildingDefaultLogger() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            appContext: appContext,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
        defer { LoggingFeature.instance = nil }

        let logger = DDLogger.builder().build().sdkLogger

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(logBuilder.serviceName, "ios")
        XCTAssertEqual(logBuilder.loggerName, "com.datadog.sdk-unit-tests")
        XCTAssertNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNil(logBuilder.carrierInfoProvider)

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Customized logger

    func testBuildingCustomizedLogger() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            appContext: appContext,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
        defer { LoggingFeature.instance = nil }

        let builder = DDLogger.builder()
        _ = builder.set(serviceName: "custom service name")
        _ = builder.set(loggerName: "custom logger name")
        _ = builder.sendNetworkInfo(true)

        let objcLogger = builder.build()
        let logger = objcLogger.sdkLogger

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(logBuilder.serviceName, "custom service name")
        XCTAssertEqual(logBuilder.loggerName, "custom logger name")
        XCTAssertNotNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNotNil(logBuilder.carrierInfoProvider)

        server.waitAndAssertNoRequestsSent()
    }

    func testUsingDifferentOutputs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { LoggingFeature.instance = nil }

        assertThat(
            logger: {
                let builder = DDLogger.builder()
                return builder.build()
            }(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(true)
                return builder.build()
            }(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(false)
                return builder.build()
            }(),
            usesOutput: NoOpLogOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.printLogsToConsole(true)
                return builder.build()
            }(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.printLogsToConsole(false)
                return builder.build()
            }(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(true)
                _ = builder.printLogsToConsole(true)
                return builder.build()
            }(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(false)
                _ = builder.printLogsToConsole(true)
                return builder.build()
            }(),
            usesOutput: LogConsoleOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(true)
                _ = builder.printLogsToConsole(false)
                return builder.build()
            }(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: {
                let builder = DDLogger.builder()
                _ = builder.sendLogsToDatadog(false)
                _ = builder.printLogsToConsole(false)
                return builder.build()
            }(),
            usesOutput: NoOpLogOutput.self
        )

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Initialization

    func testGivenDatadogNotInitialized_whenBuildingLogger_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let logger = DDLogger.builder().build()
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        assertThat(logger: logger, usesOutput: NoOpLogOutput.self)
    }

    // MARK: - Helpers

    private func assertThat(logger objcLogger: DDLogger, usesOutput outputType: LogOutput.Type, file: StaticString = #file, line: UInt = #line) {
        let logger = objcLogger.sdkLogger
        XCTAssertTrue(type(of: logger.logOutput) == outputType, file: file, line: line)
    }

    private func assertThat(logger objcLogger: DDLogger, usesCombinedOutputs outputTypes: [LogOutput.Type], file: StaticString = #file, line: UInt = #line) {
        let logger = objcLogger.sdkLogger
        if let combinedOutputs = (logger.logOutput as? CombinedLogOutput)?.combinedOutputs {
            XCTAssertEqual(outputTypes.count, combinedOutputs.count, file: file, line: line)
            outputTypes.forEach { outputType in
                XCTAssertTrue(combinedOutputs.contains { type(of: $0) == outputType }, file: file, line: line)
            }
        } else {
            XCTFail(file: file, line: line)
        }
    }
}
