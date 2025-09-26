/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogLogs

class LoggerTests: XCTestCase {
    private var core: SingleFeatureCoreMock<LogsFeature>! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = SingleFeatureCoreMock(context: .mockWith(applicationBundleIdentifier: "com.datadog.unit-tests"))
        Logs.enable(in: core)
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testDefaultLogger() throws {
        let logger = Logger.create(in: core)

        let remoteLogger = try XCTUnwrap(logger as? RemoteLogger)
        XCTAssertNil(remoteLogger.configuration.service)
        XCTAssertNil(remoteLogger.configuration.name)
        XCTAssertFalse(remoteLogger.configuration.networkInfoEnabled)
        XCTAssertEqual(remoteLogger.configuration.threshold, .debug)
        XCTAssertEqual(remoteLogger.configuration.sampler.samplingRate, 100)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertTrue(remoteLogger.rumContextIntegration)
        XCTAssertTrue(remoteLogger.activeSpanIntegration)
    }

    func testDefaultLoggerWithRUMEnabled() throws {
        let logger1 = Logger.create(in: core)
        XCTAssertTrue(try XCTUnwrap(logger1 as? RemoteLogger).rumContextIntegration)

        let logger2 = Logger.create(
            with: Logger.Configuration(
                bundleWithRumEnabled: false
            ),
            in: core
        )
        XCTAssertFalse(try XCTUnwrap(logger2 as? RemoteLogger).rumContextIntegration)
    }

    func testDefaultLoggerWithTracingEnabled() throws {
        let logger1 = Logger.create(in: core)
        XCTAssertTrue(try XCTUnwrap(logger1 as? RemoteLogger).activeSpanIntegration)

        let logger2 = Logger.create(
            with: Logger.Configuration(
                bundleWithTraceEnabled: false
            ),
            in: core
        )
        XCTAssertFalse(try XCTUnwrap(logger2 as? RemoteLogger).activeSpanIntegration)
    }

    func testCustomizedLogger() throws {
        let logger = Logger.create(
            with: Logger.Configuration(
                service: "custom-service-name",
                name: "custom-logger-name",
                networkInfoEnabled: true,
                bundleWithRumEnabled: false,
                bundleWithTraceEnabled: false,
                remoteSampleRate: 50,
                remoteLogThreshold: .error
            ),
            in: core
        )

        let remoteLogger = try XCTUnwrap(logger as? RemoteLogger)
        XCTAssertEqual(remoteLogger.configuration.service, "custom-service-name")
        XCTAssertEqual(remoteLogger.configuration.name, "custom-logger-name")
        XCTAssertTrue(remoteLogger.configuration.networkInfoEnabled)
        XCTAssertEqual(remoteLogger.configuration.threshold, .error)
        XCTAssertNil(remoteLogger.configuration.eventMapper)
        XCTAssertFalse(remoteLogger.rumContextIntegration)
        XCTAssertFalse(remoteLogger.activeSpanIntegration)
        XCTAssertEqual(remoteLogger.configuration.sampler.samplingRate, 50)
    }

    func testCombiningInternalLoggers() throws {
        var logger: LoggerProtocol

        logger = Logger.create(in: core)
        XCTAssertTrue(logger is RemoteLogger)

        logger = Logger.create(with: Logger.Configuration(remoteSampleRate: .random(in: 1...100)), in: core)
        XCTAssertTrue(logger is RemoteLogger)

        logger = Logger.create(with: Logger.Configuration(remoteSampleRate: 0), in: core)
        XCTAssertTrue(logger is NOPLogger)

        logger = Logger.create(with: Logger.Configuration(consoleLogFormat: .short), in: core)
        var combinedLogger = try XCTUnwrap(logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = Logger.create(with: Logger.Configuration(consoleLogFormat: nil), in: core)
        XCTAssertTrue(logger is RemoteLogger)

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 100,
                consoleLogFormat: .short
            ),
            in: core
        )
        combinedLogger = try XCTUnwrap(logger as? CombinedLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[0] is RemoteLogger)
        XCTAssertTrue(combinedLogger.combinedLoggers[1] is ConsoleLogger)

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: .short
            ),
            in: core
        )
        XCTAssertTrue(logger is ConsoleLogger)

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 100,
                consoleLogFormat: nil
            ),
            in: core
        )
        XCTAssertTrue(logger is RemoteLogger)

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: nil
            ),
            in: core
        )
        XCTAssertTrue(logger is NOPLogger)
    }

    func testWhenCriticalLoggedFromInternal_itCallCompletionOnce() throws {
        let completionExpectation = expectation(description: "Error processing completion")
        completionExpectation.assertForOverFulfill = true

        // Given
        let logger = Logger.create(with: Logger.Configuration(consoleLogFormat: .short), in: core)

        // When
        logger._internal.critical(
            message: "test",
            error: nil,
            attributes: nil,
            completionHandler: completionExpectation.fulfill
        )

        // Then
        wait(for: [completionExpectation], timeout: 0)
        XCTAssertTrue(logger is CombinedLogger)
    }

    func testConfiguration_withDebug_itDisableSampling() throws {
        //Given
        var config = Logger.Configuration(remoteSampleRate: 50)
        config.processInfo = ProcessInfoMock(arguments: [LaunchArguments.Debug])

        // When
        let logger = Logger.create(with: config, in: core)

        // Then
        let remoteLogger = try XCTUnwrap(logger as? RemoteLogger)
        XCTAssertEqual(remoteLogger.configuration.sampler.samplingRate, 100)
    }
}
