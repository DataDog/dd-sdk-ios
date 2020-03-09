/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Sending logs

    func testSendingMinimalLogWithDefaultLogger() throws {
        try DatadogInstanceMock.builder
            .with(
                appContext: .mockWith(
                    bundleIdentifier: "com.datadoghq.ios-sdk",
                    bundleVersion: "1.0.0",
                    bundleShortVersion: "1.0.0"
                )
            )
            .with(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            )
            .with(networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny())
            .with(carrierInfoProvider: CarrierInfoProviderMock.mockAny())
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                try logMatcher.assertItFullyMatches(jsonString: """
                {
                  "status" : "DEBUG",
                  "message" : "message",
                  "service" : "ios",
                  "logger.name" : "com.datadoghq.ios-sdk",
                  "logger.version": "\(sdkVersion)",
                  "logger.thread_name" : "main",
                  "date" : "2019-12-15T10:00:00Z",
                  "application.version": "1.0.0"
                }
                """)
            }
            .destroy()
    }

    func testSendingLogWithCustomizedLogger() throws {
        try DatadogInstanceMock.builder
            .with(networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny())
            .with(carrierInfoProvider: CarrierInfoProviderMock.mockAny())
            .initialize()
            .run {
                let logger = Logger.builder
                    .set(serviceName: "custom-service-name")
                    .set(loggerName: "custom-logger-name")
                    .sendNetworkInfo(true)
                    .build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                logMatcher.assertServiceName(equals: "custom-service-name")
                logMatcher.assertLoggerName(equals: "custom-logger-name")
                logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.name", isTypeOf: String.self)
                logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.iso_country", isTypeOf: String.self)
                logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.technology", isTypeOf: String.self)
                logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", isTypeOf: Bool.self)
                logMatcher.assertValue(forKeyPath: "network.client.available_interfaces", isTypeOf: [String].self)
                logMatcher.assertValue(forKeyPath: "network.client.reachability", isTypeOf: String.self)
                logMatcher.assertValue(forKeyPath: "network.client.is_expensive", isTypeOf: Bool.self)
                logMatcher.assertValue(forKeyPath: "network.client.supports_ipv4", isTypeOf: Bool.self)
                logMatcher.assertValue(forKeyPath: "network.client.supports_ipv6", isTypeOf: Bool.self)
                if #available(iOS 13.0, macOS 10.15, *) {
                    logMatcher.assertValue(forKeyPath: "network.client.is_constrained", isTypeOf: Bool.self)
                }
            }
            .destroy()
    }

    func testSendingLogsWithDifferentLevels() throws {
        try DatadogInstanceMock.builder
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
                logger.info("message")
                logger.notice("message")
                logger.warn("message")
                logger.error("message")
                logger.critical("message")
            }
            .waitUntil(numberOfLogsSent: 6)
            .verifyAll { logMatchers in
                logMatchers[0].assertStatus(equals: "DEBUG")
                logMatchers[1].assertStatus(equals: "INFO")
                logMatchers[2].assertStatus(equals: "NOTICE")
                logMatchers[3].assertStatus(equals: "WARN")
                logMatchers[4].assertStatus(equals: "ERROR")
                logMatchers[5].assertStatus(equals: "CRITICAL")
            }
            .destroy()
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        try DatadogInstanceMock.builder
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message with no user info")

                Datadog.setUserInfo(id: "abc-123", name: "Foo")
                logger.debug("message with user `id` and `name`")

                Datadog.setUserInfo(id: "abc-123", name: "Foo", email: "foo@example.com")
                logger.debug("message with user `id`, `name` and `email`")

                Datadog.setUserInfo(id: nil, name: nil, email: nil)
                logger.debug("message with no user info")
            }
            .waitUntil(numberOfLogsSent: 4)
            .verifyAll { logMatchers in
                logMatchers[0].assertUserInfo(equals: nil)
                logMatchers[1].assertUserInfo(equals: (id: "abc-123", name: "Foo", email: nil))
                logMatchers[2].assertUserInfo(equals: (id: "abc-123", name: "Foo", email: "foo@example.com"))
                logMatchers[3].assertUserInfo(equals: nil)
            }
            .destroy()
    }

    // MARK: - Sending carrier info

    func testSendingCarrierInfoWhenEnteringAndLeavingCellularServiceRange() throws {
        let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: nil)
        try DatadogInstanceMock.builder
            .with(carrierInfoProvider: carrierInfoProvider)
            .initialize()
            .run {
                let logger = Logger.builder
                    .sendNetworkInfo(true)
                    .build()

                // simulate entering cellular service range
                carrierInfoProvider.current = .mockWith(
                    carrierName: "Carrier",
                    carrierISOCountryCode: "US",
                    carrierAllowsVOIP: true,
                    radioAccessTechnology: .LTE
                )

                logger.debug("message")

                // simulate leaving cellular service range
                carrierInfoProvider.current = nil

                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 2)
            .verifyAll { logMatchers in
                logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.name", equals: "Carrier")
                logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.iso_country", equals: "US")
                logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.technology", equals: "LTE")
                logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", equals: true)
                logMatchers[1].assertNoValue(forKeyPath: "network.client.sim_carrier")
            }
            .destroy()
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()
        try DatadogInstanceMock.builder
            .with(networkConnectionInfoProvider: networkConnectionInfoProvider)
            .initialize()
            .run {
                let logger = Logger.builder
                    .sendNetworkInfo(true)
                    .build()

                // simulate reachable network
                networkConnectionInfoProvider.current = .mockWith(
                    reachability: .yes,
                    availableInterfaces: [.wifi, .cellular],
                    supportsIPv4: true,
                    supportsIPv6: true,
                    isExpensive: false,
                    isConstrained: false
                )

                logger.debug("message")

                // simulate unreachable network
                networkConnectionInfoProvider.current = .mockWith(
                    reachability: .no,
                    availableInterfaces: [],
                    supportsIPv4: false,
                    supportsIPv6: false,
                    isExpensive: false,
                    isConstrained: false
                )

                logger.debug("message")

                // put the network back online so last log can be send
                networkConnectionInfoProvider.current = .mockWith(reachability: .yes)
            }
            .waitUntil(numberOfLogsSent: 2)
            .verifyAll { logMatchers in
                logMatchers[0].assertValue(forKeyPath: "network.client.reachability", equals: "yes")
                logMatchers[0].assertValue(forKeyPath: "network.client.available_interfaces", equals: ["wifi", "cellular"])
                logMatchers[0].assertValue(forKeyPath: "network.client.is_constrained", equals: false)
                logMatchers[0].assertValue(forKeyPath: "network.client.is_expensive", equals: false)
                logMatchers[0].assertValue(forKeyPath: "network.client.supports_ipv4", equals: true)
                logMatchers[0].assertValue(forKeyPath: "network.client.supports_ipv6", equals: true)

                logMatchers[1].assertValue(forKeyPath: "network.client.reachability", equals: "no")
                logMatchers[1].assertValue(forKeyPath: "network.client.available_interfaces", equals: [String]())
                logMatchers[1].assertValue(forKeyPath: "network.client.is_constrained", equals: false)
                logMatchers[1].assertValue(forKeyPath: "network.client.is_expensive", equals: false)
                logMatchers[1].assertValue(forKeyPath: "network.client.supports_ipv4", equals: false)
                logMatchers[1].assertValue(forKeyPath: "network.client.supports_ipv6", equals: false)
            }
            .destroy()
    }

    // MARK: - Sending attributes

    func testSendingLoggerAttributesOfDifferentEncodableValues() throws {
        try DatadogInstanceMock.builder
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // string literal
                logger.addAttribute(forKey: "string", value: "hello")

                // boolean literal
                logger.addAttribute(forKey: "bool", value: true)

                // integer literal
                logger.addAttribute(forKey: "int", value: 10)

                // Typed 8-bit unsigned Integer
                logger.addAttribute(forKey: "uint-8", value: UInt8(10))

                // double-precision, floating-point value
                logger.addAttribute(forKey: "double", value: 10.5)

                // array of `Encodable` integer
                logger.addAttribute(forKey: "array-of-int", value: [1, 2, 3])

                // dictionary of `Encodable` date types
                logger.addAttribute(forKey: "dictionary-of-date", value: [
                    "date1": Date.mockDecember15th2019At10AMUTC(),
                    "date2": Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 60 * 60)
                ])

                struct Person: Codable {
                    let name: String
                    let age: Int
                    let nationality: String
                }

                // custom `Encodable` structure
                logger.addAttribute(forKey: "person", value: Person(name: "Adam", age: 30, nationality: "Polish"))

                // nested string literal
                logger.addAttribute(forKey: "nested.string", value: "hello")

                logger.info("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                logMatcher.assertValue(forKey: "string", equals: "hello")
                logMatcher.assertValue(forKey: "bool", equals: true)
                logMatcher.assertValue(forKey: "int", equals: 10)
                logMatcher.assertValue(forKey: "uint-8", equals: UInt8(10))
                logMatcher.assertValue(forKey: "double", equals: 10.5)
                logMatcher.assertValue(forKey: "array-of-int", equals: [1, 2, 3])
                logMatcher.assertValue(forKeyPath: "dictionary-of-date.date1", equals: "2019-12-15T10:00:00Z")
                logMatcher.assertValue(forKeyPath: "dictionary-of-date.date2", equals: "2019-12-15T11:00:00Z")
                logMatcher.assertValue(forKeyPath: "person.name", equals: "Adam")
                logMatcher.assertValue(forKeyPath: "person.age", equals: 30)
                logMatcher.assertValue(forKeyPath: "person.nationality", equals: "Polish")
                logMatcher.assertValue(forKeyPath: "nested.string", equals: "hello")
            }
            .destroy()
    }

    func testSendingMessageAttributes() throws {
        try DatadogInstanceMock.builder
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // add logger attribute
                logger.addAttribute(forKey: "attribute", value: "logger's value")

                // send message with no attributes
                logger.info("info message 1")

                // send message with attribute overriding logger's attribute
                logger.info("info message 2", attributes: ["attribute": "message's value"])

                // remove logger attribute
                logger.removeAttribute(forKey: "attribute")

                // send message
                logger.info("info message 3")
            }
            .waitUntil(numberOfLogsSent: 3)
            .verifyAll { logMatchers in
                logMatchers[0].assertValue(forKey: "attribute", equals: "logger's value")
                logMatchers[1].assertValue(forKey: "attribute", equals: "message's value")
                logMatchers[2].assertNoValue(forKey: "attribute")
            }
            .destroy()
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        try DatadogInstanceMock.builder
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // add tag
                logger.add(tag: "tag1")

                // send message
                logger.info("info message 1")

                // add tag with key
                logger.addTag(withKey: "tag2", value: "abcd")

                // send message
                logger.info("info message 2")

                // remove tag with key
                logger.removeTag(withKey: "tag2")

                // remove tag
                logger.remove(tag: "tag1")

                // send message
                logger.info("info message 3")
            }
            .waitUntil(numberOfLogsSent: 3)
            .verifyAll { logMatchers in
                logMatchers[0].assertTags(equal: ["tag1"])
                logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd"])
                logMatchers[2].assertNoValue(forKey: LogEncoder.StaticCodingKeys.tags.rawValue)
            }
            .destroy()
    }

    // MARK: - Customizing outputs

    func testUsingDifferentOutputs() throws {
        Datadog.instance = .mockNeverPerformingUploads()

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
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(),
            usesOutput: LogConsoleOutput.self
        )
        assertThat(
            logger: Logger.builder.printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(),
            usesOutput: NoOpLogOutput.self
        )

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Sending logs with different network and battery conditions

    func testGivenBadBatteryConditions_itDoesntTryToSendLogs() throws {
        try DatadogInstanceMock.builder
            .with(
                batteryStatusProvider: BatteryStatusProviderMock.mockWith(
                    status: .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                )
            )
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyNoLogsSent()
            .destroy()
    }

    func testGivenNoNetworkConnection_itDoesNotTryToSendLogs() throws {
        try DatadogInstanceMock.builder
            .with(
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                    networkConnectionInfo: .mockWith(reachability: .no)
                )
            )
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyNoLogsSent()
            .destroy()
    }

    // MARK: - Initialization

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
}
