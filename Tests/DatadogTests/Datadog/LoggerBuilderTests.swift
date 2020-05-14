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
    private var mockServer: ServerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()

        mockServer = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: mockServer,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationVersion: "1.2.3",
                applicationBundleIdentifier: "com.datadog.unit-tests",
                serviceName: "service-name",
                environment: "tests"
            ),
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }

    override func tearDown() {
        mockServer.waitAndAssertNoRequestsSent()
        LoggingFeature.instance = nil
        mockServer = nil

        temporaryDirectory.delete()
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.builder.build()

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "com.datadog.unit-tests")
        XCTAssertNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNil(logBuilder.carrierInfoProvider)
    }

    func testCustomizedLogger() throws {
        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(false)
            .build()

        guard let logBuilder = (logger.logOutput as? LogFileOutput)?.logBuilder else {
            XCTFail()
            return
        }

        XCTAssertEqual(logBuilder.applicationVersion, "1.2.3")
        XCTAssertEqual(logBuilder.serviceName, "custom-service-name")
        XCTAssertEqual(logBuilder.environment, "tests")
        XCTAssertEqual(logBuilder.loggerName, "custom-logger-name")
        XCTAssertNil(logBuilder.networkConnectionInfoProvider)
        XCTAssertNil(logBuilder.carrierInfoProvider)
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

class LoggerBuilderErrorTests: XCTestCase {
    func testGivenDatadogNotInitialized_whenBuildingLogger_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let logger = Logger.builder.build()
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        assertThat(logger: logger, usesOutput: NoOpLogOutput.self)
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
