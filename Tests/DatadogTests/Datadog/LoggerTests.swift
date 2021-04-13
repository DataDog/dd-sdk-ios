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
        XCTAssertNil(LoggingFeature.instance)
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Customizing Logger

    func testSendingLogWithDefaultLogger() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.0.0",
                    applicationBundleIdentifier: "com.datadoghq.ios-sdk",
                    serviceName: "default-service-name",
                    environment: "tests"
                )
            ),
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]
        try logMatcher.assertItFullyMatches(jsonString: """
        {
          "status" : "debug",
          "message" : "message",
          "service" : "default-service-name",
          "logger.name" : "com.datadoghq.ios-sdk",
          "logger.version": "\(sdkVersion)",
          "logger.thread_name" : "main",
          "date" : "2019-12-15T10:00:00.000Z",
          "version": "1.0.0",
          "ddtags": "env:tests"
        }
        """)
    }

    func testSendingLogWithCustomizedLogger() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .build()
        logger.debug("message")

        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]

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
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC(), advancingBySeconds: 1)
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.info("message 1")
        logger.info("message 2")
        logger.info("message 3")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 3)
        // swiftlint:disable trailing_closure
        logMatchers[0].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC() })
        logMatchers[1].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1) })
        logMatchers[2].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 2) })
        // swiftlint:enable trailing_closure
    }

    func testSendingLogsWithDifferentLevels() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 6)
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
    }

    // MARK: - Logging an error

    func testLoggingError() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        struct TestError: Error {
            var description = "Test description"
        }
        let error = TestError()

        let logger = Logger.builder.build()
        logger.debug("message", error: error)
        logger.info("message", error: error)
        logger.notice("message", error: error)
        logger.warn("message", error: error)
        logger.error("message", error: error)
        logger.critical("message", error: error)

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 6)
        for matcher in logMatchers {
            matcher.assertValue(forKeyPath: "error.stack", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.message", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.kind", equals: "TestError")
        }
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        Datadog.instance = Datadog(
            consentProvider: ConsentProvider(initialConsent: .granted),
            userInfoProvider: UserInfoProvider(),
            launchTimeProvider: LaunchTimeProviderMock()
        )
        defer { Datadog.instance = nil }

        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                userInfoProvider: Datadog.instance!.userInfoProvider
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message with no user info")

        Datadog.setUserInfo(id: "abc-123", name: "Foo")
        logger.debug("message with user `id` and `name`")

        Datadog.setUserInfo(
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

        Datadog.setUserInfo(id: nil, name: nil, email: nil)
        logger.debug("message with no user info")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 4)
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
        let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: nil)
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                carrierInfoProvider: carrierInfoProvider
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build()

        // simulate entering cellular service range
        carrierInfoProvider.set(
            current: .mockWith(
                carrierName: "Carrier",
                carrierISOCountryCode: "US",
                carrierAllowsVOIP: true,
                radioAccessTechnology: .LTE
            )
        )

        logger.debug("message")

        // simulate leaving cellular service range
        carrierInfoProvider.set(current: nil)

        logger.debug("message")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.name", equals: "Carrier")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.iso_country", equals: "US")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.technology", equals: "LTE")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", equals: true)
        logMatchers[1].assertNoValue(forKeyPath: "network.client.sim_carrier")
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build()

        // simulate reachable network
        networkConnectionInfoProvider.set(
            current: .mockWith(
                reachability: .yes,
                availableInterfaces: [.wifi, .cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: false,
                isConstrained: false
            )
        )

        logger.debug("message")

        // simulate unreachable network
        networkConnectionInfoProvider.set(
            current: .mockWith(
                reachability: .no,
                availableInterfaces: [],
                supportsIPv4: false,
                supportsIPv6: false,
                isExpensive: false,
                isConstrained: false
            )
        )

        logger.debug("message")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)
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
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

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

        // URL
        logger.addAttribute(forKey: "url", value: URL(string: "https://example.com/image.png")!)

        logger.info("message")

        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]
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
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

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

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertValue(forKey: "attribute", equals: "logger's value")
        logMatchers[1].assertValue(forKey: "attribute", equals: "message's value")
        logMatchers[2].assertNoValue(forKey: "attribute")
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(common: .mockWith(environment: "tests"))
        )
        defer { LoggingFeature.instance = nil }

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

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertTags(equal: ["tag1", "env:tests"])
        logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd", "env:tests"])
        logMatchers[2].assertTags(equal: ["env:tests"])
    }

    // MARK: - Sending logs with different network and battery conditions

    func testGivenBadBatteryConditions_itDoesNotTryToSendLogs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                mobileDevice: .mockWith(
                    currentBatteryStatus: { () -> MobileDevice.BatteryStatus in
                        .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                    }
                )
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        server.waitAndAssertNoRequestsSent()
    }

    func testGivenNoNetworkConnection_itDoesNotTryToSendLogs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                    networkConnectionInfo: .mockWith(reachability: .no)
                )
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Integration With RUM Feature

    func testGivenBundlingWithRUMEnabledAndRUMMonitorRegistered_whenSendingLog_itContainsCurrentRUMContext() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(common: .mockWith(environment: "tests"))
        )
        defer { LoggingFeature.instance = nil }

        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        // given
        let logger = Logger.builder.build()
        Global.rum = RUMMonitor.initialize()
        Global.rum.startView(viewController: mockView)
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        logger.info("info message")

        // then
        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.applicationID,
            equals: try XCTUnwrap(RUMFeature.instance?.configuration.applicationID)
        )
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.sessionID,
            isTypeOf: String.self
        )
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.viewID,
            isTypeOf: String.self
        )
    }

    func testGivenBundlingWithRUMEnabledButRUMMonitorNotRegistered_whenSendingLog_itPrintsWarning() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(common: .mockWith(environment: "tests"))
        )
        defer { LoggingFeature.instance = nil }

        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // given
        let logger = Logger.builder.build()
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // when
        logger.info("info message")

        // then
        XCTAssertEqual(output.recordedLog?.status, .warn)
        try XCTAssertTrue(
            XCTUnwrap(output.recordedLog?.message)
                .contains("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Logging will not work.")
        )

        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.applicationID)
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.sessionID)
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.viewID)
    }

    func testWhenSendingErrorOrCriticalLogs_itCreatesRUMErrorForCurrentView() throws {
        LoggingFeature.instance = .mockNoOp()
        defer { LoggingFeature.instance = nil }

        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        // given
        let logger = Logger.builder.build()
        Global.rum = RUMMonitor.initialize()
        Global.rum.startView(viewController: mockView)
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        logger.debug("debug message")
        logger.info("info message")
        logger.notice("notice message")
        logger.warn("warn message")
        logger.error("error message")
        logger.critical("critical message")

        // then
        // [RUMView, RUMAction, RUMError, RUMView, RUMError, RUMView] events sent:
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 6)
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

    // MARK: - Integration With Active Span

    func testGivenBundlingWithTraceEnabledAndTracerRegistered_whenSendingLog_itContainsActiveSpanAttributes() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        // given
        let logger = Logger.builder.build()
        Global.sharedTracer = Tracer.initialize(configuration: .init())
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // when
        let span = Global.sharedTracer.startSpan(operationName: "span").setActive()
        logger.info("info message 1")
        span.finish()
        logger.info("info message 2")

        // then
        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(
            forKeyPath: LoggingWithActiveSpanIntegration.Attributes.traceID,
            equals: "\(span.context.dd.traceID.rawValue)"
        )
        logMatchers[0].assertValue(
            forKeyPath: LoggingWithActiveSpanIntegration.Attributes.spanID,
            equals: "\(span.context.dd.spanID.rawValue)"
        )
        logMatchers[1].assertNoValue(forKey: LoggingWithActiveSpanIntegration.Attributes.traceID)
        logMatchers[1].assertNoValue(forKey: LoggingWithActiveSpanIntegration.Attributes.spanID)
    }

    func testGivenBundlingWithTraceEnabledButTracerNotRegistered_whenSendingLog_itPrintsWarning() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // given
        let logger = Logger.builder.build()
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // when
        logger.info("info message")

        // then
        XCTAssertEqual(output.recordedLog?.status, .warn)
        try XCTAssertTrue(
            XCTUnwrap(output.recordedLog?.message)
                .contains("Tracing feature is enabled, but no `Tracer` is registered. The Tracing integration with Logging will not work.")
        )

        let logMatcher = try LoggingFeature.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertNoValue(forKeyPath: LoggingWithActiveSpanIntegration.Attributes.traceID)
        logMatcher.assertNoValue(forKeyPath: LoggingWithActiveSpanIntegration.Attributes.spanID)
    }

    // MARK: - Integration With Environment Context

    func testGivenBundlingWithTraceEnabledAndTracerRegisteredAndEnvironmentContext_whenSendingLog_itContainsEnvironmentContextAttributes() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(directories: temporaryFeatureDirectories)
        defer { LoggingFeature.instance = nil }

        setenv("x-datadog-trace-id", "111111", 1)
        setenv("x-datadog-parent-id", "222222", 1)

        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        // given
        let logger = Logger.builder.build()
        Global.sharedTracer = Tracer.initialize(configuration: .init())
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // when
        let span = Global.sharedTracer.startSpan(operationName: "span").setActive()
        logger.info("info message 1")
        span.finish()
        logger.info("info message 2")

        // then
        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(
            forKeyPath: LoggingWithEnvironmentSpanIntegration.Attributes.traceID,
            equals: "\(span.context.dd.traceID.rawValue)"
        )
        logMatchers[0].assertValue(
            forKeyPath: LoggingWithEnvironmentSpanIntegration.Attributes.spanID,
            equals: "\(span.context.dd.spanID.rawValue)"
        )
        logMatchers[1].assertValue(
            forKeyPath: LoggingWithEnvironmentSpanIntegration.Attributes.traceID,
            equals: "\(TracingUUID(rawValue: 111_111).rawValue)"
        )
        logMatchers[1].assertValue(
            forKeyPath: LoggingWithEnvironmentSpanIntegration.Attributes.spanID,
            equals: "\(TracingUUID(rawValue: 222_222).rawValue)"
        )

        unsetenv("x-datadog-trace-id")
        unsetenv("x-datadog-parent-id")
    }

    // MARK: - Log Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingLogs_thenLogDateUsesServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        let serverTimeDifference = TimeInterval.random(in: -5..<5).rounded() // few seconds difference

        // When
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(using: deviceTime),
                dateCorrector: DateCorrectorMock(correctionOffset: serverTimeDifference)
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        // Then
        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 1)
        logMatchers[0].assertDate { logDate in
            logDate == deviceTime.addingTimeInterval(serverTimeDifference)
        }
    }

    // MARK: - Tracking Consent

    func testWhenChangingConsentValues_itUploadsOnlyAuthorizedLogs() throws {
        let consentProvider = ConsentProvider(initialConsent: .pending)

        // Given
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(consentProvider: consentProvider)
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()

        // When
        logger.info("message in `.pending` consent changed to `.granted`")
        consentProvider.changeConsent(to: .granted)
        logger.info("message in `.granted` consent")
        consentProvider.changeConsent(to: .notGranted)
        logger.info("message in `.notGranted` consent")
        consentProvider.changeConsent(to: .granted)
        logger.info("another message in `.granted` consent")

        // Then
        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertMessage(equals: "message in `.pending` consent changed to `.granted`")
        logMatchers[1].assertMessage(equals: "message in `.granted` consent")
        logMatchers[2].assertMessage(equals: "another message in `.granted` consent")
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockNoOp()
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendLogsToDatadog(false)
            .printLogsToConsole(false)
            .build()

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

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Usage

    func testGivenDatadogNotInitialized_whenInitializingLogger_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(Datadog.instance)

        // when
        let logger = Logger.builder.build()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        XCTAssertNil(logger.logBuilder)
        XCTAssertNil(logger.logOutput)
    }

    func testGivenLoggingFeatureDisabled_whenInitializingLogger_itPrintsError() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableLogging(false)
                .build()
        )

        // when
        let logger = Logger.builder.build()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
        )
        XCTAssertNil(logger.logBuilder)
        XCTAssertNil(logger.logOutput)

        try Datadog.deinitializeOrThrow()
    }

    func testDDLoggerIsLoggerTypealias() {
        XCTAssertTrue(DDLogger.self == Logger.self)
    }
}
// swiftlint:enable multiline_arguments_brackets
