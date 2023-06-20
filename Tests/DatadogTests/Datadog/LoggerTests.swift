/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogTrace
@testable import DatadogRUM
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    /// Enables RUM feature and creates RUM monitor for tests.
    private func createTestableRUMMonitor(configuration: RUMConfiguration = .mockAny()) throws -> Monitor {
        let rum = try RUMFeature(
            in: core,
            configuration: configuration,
            with: Monitor(
                core: core,
                dependencies: RUMScopeDependencies(core: core,configuration: configuration)
                    // disable RUM view updates sampling for deterministic test behaviour:
                    .replacing(viewUpdatesThrottlerFactory: { NoOpRUMViewUpdatesThrottler() }),
                dateProvider: configuration.dateProvider
            )
        )
        try core.register(feature: rum)
        return rum.monitor
    }

    // MARK: - Customizing Logger

    func testSendingLogWithDefaultLogger() throws {
        core.context = .mockWith(
            service: "default-service-name",
            env: "tests",
            version: "1.0.0",
            sdkVersion: "1.2.3",
            device: .mockWith(architecture: "testArch")
        )

        let feature: LogsFeature = .mockWith(
            applicationBundleIdentifier: "com.datadoghq.ios-sdk",
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        )
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        logger.debug("message")

        let logMatcher = try core.waitAndReturnLogMatchers()[0]
        try logMatcher.assertItFullyMatches(jsonString: """
        {
          "status" : "debug",
          "message" : "message",
          "service" : "default-service-name",
          "logger.name" : "com.datadoghq.ios-sdk",
          "logger.version": "1.2.3",
          "logger.thread_name" : "main",
          "date" : "2019-12-15T10:00:00.000Z",
          "version": "1.0.0",
          "ddtags": "env:tests,version:1.0.0",
          "_dd": {
            "device": {
              "architecture": "testArch"
            }
          }
        }
        """)
    }

    func testSendingLogWithCustomizedLogger() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .build(in: core)
        logger.debug("message")

        let logMatcher = try core.waitAndReturnLogMatchers()[0]

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
        if #available(iOS 13.0, *) {
            logMatcher.assertValue(forKeyPath: "network.client.is_constrained", isTypeOf: Bool.self)
        }
    }

    // MARK: - Sending Customized Logs

    func testSendingLogsWithDifferentDates() throws {
        let feature: LogsFeature = .mockWith(
            dateProvider: RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC(), advancingBySeconds: 1)
        )
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        logger.info("message 1")
        logger.info("message 2")
        logger.info("message 3")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC() })
        logMatchers[1].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1) })
        logMatchers[2].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 2) })
    }

    func testSendingLogsWithDifferentLevels() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
    }

    func testSendingLogsAboveCertainLevel() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .set(datadogReportingThreshold: .warn)
            .build(in: core)

        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertStatus(equals: "warn")
        logMatchers[1].assertStatus(equals: "error")
        logMatchers[2].assertStatus(equals: "critical")
    }

    // MARK: - Logging an error

    func testLoggingError() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        struct TestError: Error {
            var description = "Test description"
        }
        let error = TestError()

        let logger = DatadogLogger.builder.build(in: core)
        logger.debug("message", error: error)
        logger.info("message", error: error)
        logger.notice("message", error: error)
        logger.warn("message", error: error)
        logger.error("message", error: error)
        logger.critical("message", error: error)

        let logMatchers = try core.waitAndReturnLogMatchers()
        for matcher in logMatchers {
            matcher.assertValue(forKeyPath: "error.stack", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.message", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.kind", equals: "TestError")
        }
    }

    func testLoggingErrorStrings() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        let errorKind = String.mockRandom()
        let errorMessage = String.mockRandom()
        let stackTrace = String.mockRandom()
        logger.log(level: .info,
                   message: .mockAny(),
                   errorKind: errorKind,
                   errorMessage: errorMessage,
                   stackTrace: stackTrace,
                   attributes: nil
        )

        let logMatchers = try core.waitAndReturnLogMatchers()
        let logMatcher = logMatchers.first
        XCTAssertNotNil(logMatcher)
        if let logMatcher = logMatcher {
            logMatcher.assertValue(forKeyPath: "error.kind", equals: errorKind)
            logMatcher.assertValue(forKeyPath: "error.message", equals: errorMessage)
            logMatcher.assertValue(forKeyPath: "error.stack", equals: stackTrace)
        }
    }

    // MARK: - Sampling

    func testSamplingEnabled() throws {
        core.context = .mockAny()
        let feature: LogsFeature = .mockWith(
            sampler: .mockKeepAll()
        )
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .build(in: core)

        logger.debug(.mockAny())
        logger.info(.mockAny())
        logger.notice(.mockAny())
        logger.warn(.mockAny())
        logger.error(.mockAny())
        logger.critical(.mockAny())

        XCTAssertEqual(try core.waitAndReturnLogMatchers().count, 6)
    }

    func testSamplingDisabled() throws {
        core.context = .mockAny()
        let feature: LogsFeature = .mockWith(
            sampler: .mockRejectAll()
        )
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .build(in: core)

        logger.debug(.mockAny())
        logger.info(.mockAny())
        logger.notice(.mockAny())
        logger.warn(.mockAny())
        logger.error(.mockAny())
        logger.critical(.mockAny())

        XCTAssertEqual(try core.waitAndReturnLogMatchers().count, 0)
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        core.context = .mockWith(
            userInfo: .empty
        )

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)

        logger.debug("message with no user info")

        core.context.userInfo = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        logger.debug("message with user `id` and `name`")

        core.context.userInfo = UserInfo(
            id: "abc-123",
            name: "Foo",
            email: "foo@example.com",
            extraInfo: [
                "str": "value",
                "int": 11_235,
                "bool": true
            ]
        )
        logger.debug("message with user `id`, `name`, `email` and `extraInfo`")

        core.context.userInfo = .empty
        logger.debug("message with no user info")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertUserInfo(equals: nil)

        logMatchers[1].assertUserInfo(equals: (id: "abc-123", name: "Foo", email: nil))

        logMatchers[2].assertUserInfo(
            equals: (
                id: "abc-123",
                name: "Foo",
                email: "foo@example.com"
            )
        )
        logMatchers[2].assertValue(forKey: "usr.str", equals: "value")
        logMatchers[2].assertValue(forKey: "usr.int", equals: 11_235)
        logMatchers[2].assertValue(forKey: "usr.bool", equals: true)

        logMatchers[3].assertUserInfo(equals: nil)
    }

    // MARK: - Sending carrier info

    func testSendingCarrierInfoWhenEnteringAndLeavingCellularServiceRange() throws {
        core.context = .mockWith(
            carrierInfo: nil
        )

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .sendNetworkInfo(true)
            .build(in: core)

        // simulate entering cellular service range
        core.context.carrierInfo = .mockWith(
            carrierName: "Carrier",
            carrierISOCountryCode: "US",
            carrierAllowsVOIP: true,
            radioAccessTechnology: .LTE
        )

        logger.debug("message")

        // simulate leaving cellular service range
        core.context.carrierInfo = nil

        logger.debug("message")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.name", equals: "Carrier")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.iso_country", equals: "US")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.technology", equals: "LTE")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", equals: true)
        logMatchers[1].assertNoValue(forKeyPath: "network.client.sim_carrier")
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        core.context = .mockWith(
            networkConnectionInfo: nil
        )

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder
            .sendNetworkInfo(true)
            .build(in: core)

        // simulate reachable network
        core.context.networkConnectionInfo = .mockWith(
            reachability: .yes,
            availableInterfaces: [.wifi, .cellular],
            supportsIPv4: true,
            supportsIPv6: true,
            isExpensive: false,
            isConstrained: false
        )

        logger.debug("message")

        // simulate unreachable network
        core.context.networkConnectionInfo = .mockWith(
            reachability: .no,
            availableInterfaces: [],
            supportsIPv4: false,
            supportsIPv6: false,
            isExpensive: false,
            isConstrained: false
        )

        logger.debug("message")

        let logMatchers = try core.waitAndReturnLogMatchers()
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

    // MARK: - Sending attributes

    func testSendingLoggerAttributesOfDifferentEncodableValues() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)

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

        // URL
        logger.addAttribute(forKey: "url", value: URL(string: "https://example.com/image.png")!)

        logger.info("message")

        let logMatcher = try core.waitAndReturnLogMatchers()[0]
        logMatcher.assertValue(forKey: "string", equals: "hello")
        logMatcher.assertValue(forKey: "bool", equals: true)
        logMatcher.assertValue(forKey: "int", equals: 10)
        logMatcher.assertValue(forKey: "uint-8", equals: UInt8(10))
        logMatcher.assertValue(forKey: "double", equals: 10.5)
        logMatcher.assertValue(forKey: "array-of-int", equals: [1, 2, 3])
        logMatcher.assertValue(forKeyPath: "dictionary-of-date.date1", equals: "2019-12-15T10:00:00.000Z")
        logMatcher.assertValue(forKeyPath: "dictionary-of-date.date2", equals: "2019-12-15T11:00:00.000Z")
        logMatcher.assertValue(forKeyPath: "person.name", equals: "Adam")
        logMatcher.assertValue(forKeyPath: "person.age", equals: 30)
        logMatcher.assertValue(forKeyPath: "person.nationality", equals: "Polish")
        logMatcher.assertValue(forKeyPath: "nested.string", equals: "hello")
        /// URLs are encoded explicitly as `String` - see the comment in `EncodableValue`
        logMatcher.assertValue(forKeyPath: "url", equals: "https://example.com/image.png")
    }

    func testSendingMessageAttributes() throws {
        core.context = .mockAny()

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)

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

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertValue(forKey: "attribute", equals: "logger's value")
        logMatchers[1].assertValue(forKey: "attribute", equals: "message's value")
        logMatchers[2].assertNoValue(forKey: "attribute")
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        core.context = .mockWith(
            env: "tests",
            version: "1.2.3"
        )

        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)

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

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertTags(equal: ["tag1", "env:tests", "version:1.2.3"])
        logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd", "env:tests", "version:1.2.3"])
        logMatchers[2].assertTags(equal: ["env:tests", "version:1.2.3"])
    }

    // MARK: - Integration With RUM Feature

    func testGivenBundlingWithRUMEnabledAndRUMFeatureEnabled_whenSendingLogBeforeAnyUserActivity_itContainsSessionId() throws {
        core.context = .mockAny()

        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        RUM.enable(with: .mockWith(sessionSampler: .mockKeepAll()), in: core)

        // given
        let logger = DatadogLogger.builder.bundleWithRUM(true).build(in: core)

        // when
        logger.info("message 0")

        // then
        let logMatchers = try core.waitAndReturnLogMatchers()
        XCTAssertEqual(logMatchers.count, 1)

        logMatchers.forEach {
            $0.assertValue(
                forKeyPath: RUMContextAttributes.IDs.sessionID,
                isTypeOf: String.self
            )
        }
    }

    func testGivenBundlingWithRUMEnabledAndRUMFeatureEnabled_whenSendingLog_itContainsCurrentRUMContext() throws {
        core.context = .mockAny()

        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        let applicationID: String = .mockRandom()
        RUM.enable(with: .mockWith(
            applicationID: applicationID,
            sessionSampler: .mockKeepAll()
        ), in: core)

        // given
        let logger = DatadogLogger.builder.bundleWithRUM(true).build(in: core)

        // when
        RUMMonitor.shared(in: core).startView(viewController: mockView)
        logger.info("message 0")
        RUMMonitor.shared(in: core).startAction(type: .tap, name: .mockAny())
        logger.info("message 1")

        // then
        let logMatchers = try core.waitAndReturnLogMatchers()
        XCTAssertEqual(logMatchers.count, 2)

        logMatchers.forEach {
            $0.assertValue(
                forKeyPath: RUMContextAttributes.IDs.applicationID,
                equals: applicationID
            )

            $0.assertValue(
                forKeyPath: RUMContextAttributes.IDs.sessionID,
                isTypeOf: String.self
            )

            $0.assertValue(
                forKeyPath: RUMContextAttributes.IDs.viewID,
                isTypeOf: String.self
            )
        }

        logMatchers.first?.assertNoValue(forKeyPath: RUMContextAttributes.IDs.userActionID)

        logMatchers.last?.assertValue(
            forKeyPath: RUMContextAttributes.IDs.userActionID,
            isTypeOf: String.self
        )
    }

    func testWhenSendingErrorOrCriticalLogs_itCreatesRUMErrorForCurrentView() throws {
        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        // given
        let logger = DatadogLogger.builder.build(in: core)
        let rum = try createTestableRUMMonitor()
        rum.startView(viewController: mockView)

        // when
        logger.debug("debug message")
        logger.info("info message")
        logger.notice("notice message")
        logger.warn("warn message")
        logger.error("error message")
        logger.critical("critical message")

        // then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let rumErrorMatcher1 = rumEventMatchers.first { $0.model(isTypeOf: RUMErrorEvent.self) }
        let rumErrorMatcher2 = rumEventMatchers.last { $0.model(isTypeOf: RUMErrorEvent.self) }
        try XCTUnwrap(rumErrorMatcher1).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "error message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
        }
        try XCTUnwrap(rumErrorMatcher2).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "critical message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
        }
    }

    func testWhenSendingErrorOrCriticalLogsWithAttributes_itCreatesRUMErrorForCurrentViewWithAttributes() throws {
        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        // given
        let logger = DatadogLogger.builder.build(in: core)
        let rum = try createTestableRUMMonitor()
        rum.startView(viewController: mockView)

        // when
        let attributeValueA: String = .mockRandom()
        logger.error("error message", attributes: [
            "any_attribute_a": attributeValueA
        ])
        let attributeValueB: String = .mockRandom()
        logger.critical("critical message", attributes: [
            "any_attribute_b": attributeValueB
        ])

        // then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let rumErrorMatcher1 = rumEventMatchers.first { $0.model(isTypeOf: RUMErrorEvent.self) }
        let rumErrorMatcher2 = rumEventMatchers.last { $0.model(isTypeOf: RUMErrorEvent.self) }
        try XCTUnwrap(rumErrorMatcher1).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "error message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
            let attributeValue = (rumModel.context?.contextInfo["any_attribute_a"] as? AnyCodable)?.value as? String
            XCTAssertEqual(attributeValue, attributeValueA)
        }
        try XCTUnwrap(rumErrorMatcher2).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "critical message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
            let attributeValue = (rumModel.context?.contextInfo["any_attribute_b"] as? AnyCodable)?.value as? String
            XCTAssertEqual(attributeValue, attributeValueB)
        }
    }

    func testWhenSendingErrorOrCriticalLogs_itCreatesRUMErrorWithProperSourceType() throws {
        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        // given
        let logger = DatadogLogger.builder.build(in: core)
        let rum = try createTestableRUMMonitor()
        rum.startView(viewController: mockView)

        // when
        logger.error("error message", attributes: [
            "_dd.error.source_type": "flutter"
        ])
        logger.critical("critical message", attributes: [
            "_dd.error.source_type": "react-native"
        ])

        // then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let rumErrorMatcher1 = rumEventMatchers.first { $0.model(isTypeOf: RUMErrorEvent.self) }
        let rumErrorMatcher2 = rumEventMatchers.last { $0.model(isTypeOf: RUMErrorEvent.self) }
        try XCTUnwrap(rumErrorMatcher1).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "error message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
            XCTAssertEqual(rumModel.error.sourceType, .flutter)
        }
        try XCTUnwrap(rumErrorMatcher2).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "critical message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
            XCTAssertEqual(rumModel.error.sourceType, .reactNative)
        }
    }

    func testWhenSendingErrorOrCriticalLogs_itCreatesRUMErrorWithProperIsCrash() throws {
        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        // given
        let logger = DatadogLogger.builder.build(in: core)
        let rum = try createTestableRUMMonitor()
        rum.startView(viewController: mockView)

        // when
        logger.error("error message", attributes: [
            "_dd.error.is_crash": false
        ])
        logger.critical("critical message", attributes: [
            "_dd.error.is_crash": true
        ])

        // then
        let errorEvents = core.waitAndReturnEvents(ofFeature: DatadogRUMFeature.name, ofType: RUMErrorEvent.self)
        let error1 = try XCTUnwrap(errorEvents.first)
        XCTAssertEqual(error1.error.message, "error message")
        XCTAssertEqual(error1.error.source, .logger)
        XCTAssertNil(error1.error.stack)
        // swiftlint:disable:next xct_specific_matcher
        XCTAssertEqual(error1.error.isCrash, false)

        let error2 = try XCTUnwrap(errorEvents.last)
        XCTAssertEqual(error2.error.message, "critical message")
        XCTAssertEqual(error2.error.source, .logger)
        XCTAssertNil(error2.error.stack)
        // swiftlint:disable:next xct_specific_matcher
        XCTAssertEqual(error2.error.isCrash, true)
    }

    // MARK: - Integration With Active Span

    func testGivenBundlingWithTraceEnabledAndTracerRegistered_whenSendingLog_itContainsActiveSpanAttributes() throws {
        core.context = .mockAny()

        let logging: LogsFeature = .mockAny()
        try core.register(feature: logging)

        DatadogTracer.initialize(in: core)

        // given
        let logger = DatadogLogger.builder.build(in: core)

        DatadogTracer.initialize(in: core)
        let tracer = DatadogTracer.shared(in: core)

        // when
        let span = tracer.startSpan(operationName: "span").setActive()
        logger.info("info message 1")
        span.finish()
        logger.info("info message 2")

        // then
        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertValue(
            forKeyPath: "dd.trace_id",
            equals: String(span.context.dd.traceID)
        )
        logMatchers[0].assertValue(
            forKeyPath: "dd.span_id",
            equals: String(span.context.dd.spanID)
        )
        logMatchers[1].assertNoValue(forKey: "dd.trace_id")
        logMatchers[1].assertNoValue(forKey: "dd.span_id")
    }

    // MARK: - Log Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingLogs_thenLogDateUsesServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        let serverTimeOffset = TimeInterval.random(in: -5..<5).rounded() // few seconds difference

        core.context = .mockWith(
            serverTimeOffset: serverTimeOffset
        )

        // When
        let feature: LogsFeature = .mockWith(dateProvider: RelativeDateProvider(using: deviceTime))
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        logger.debug("message")

        // Then
        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertDate { logDate in
            logDate == deviceTime.addingTimeInterval(serverTimeOffset)
        }
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() throws {
        let feature: LogsFeature = .mockAny()
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 3

            switch modulo {
            case 0:
                logger.debug("message")
                logger.debug("message", attributes: ["attribute": "value"])
            case 1:
                logger.addAttribute(forKey: "att\(modulo)", value: "value")
                logger.addTag(withKey: "t\(modulo)", value: "value")
            case 2:
                logger.removeAttribute(forKey: "att\(modulo)")
                logger.removeTag(withKey: "att\(modulo)")
            default:
                break
            }
        }
    }

    // MARK: - Usage

    func testGivenDatadogNotInitialized_whenInitializingLogger_itPrintsError() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        let core = NOPDatadogCore()

        // when
        let logger = DatadogLogger.builder.build(in: core)

        // then
        XCTAssertEqual(
            dd.logger.criticalLog?.message,
            "Failed to build `Logger`."
        )
        XCTAssertEqual(
            dd.logger.criticalLog?.error?.message,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        XCTAssertTrue(logger.logger is NOPLogger)
    }

    func testGivenLoggingFeatureDisabled_whenInitializingLogger_itPrintsError() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        core.context = .mockAny()
        XCTAssertNil(core.get(feature: LogsFeature.self))

        // when
        let logger = DatadogLogger.builder.build(in: core)

        // then
        XCTAssertEqual(
            dd.logger.criticalLog?.message,
            "Failed to build `Logger`."
        )
        XCTAssertEqual(
            dd.logger.criticalLog?.error?.message,
            "🔥 Datadog SDK usage error: `Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
        )
        XCTAssertTrue(logger.logger is NOPLogger)
    }
}
// swiftlint:enable multiline_arguments_brackets
