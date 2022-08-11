/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    private var core: DatadogCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreMock()
    }

    override func tearDown() {
        core.flush()
        core = nil
        super.tearDown()
    }

    // MARK: - Customizing Logger

    func testSendingLogWithDefaultLogger() throws {
        core.context = .mockWith(
            service: "default-service-name",
            env: "tests",
            version: "1.0.0",
            sdkVersion: "1.2.3",
            applicationBundleIdentifier: "com.datadoghq.ios-sdk",
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        )

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)
        logger.debug("message")

        let logMatcher = try feature.waitAndReturnLogMatchers(count: 1)[0]
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
          "ddtags": "env:tests,version:1.0.0"
        }
        """)
    }

    func testSendingLogWithCustomizedLogger() throws {
        core.context = .mockAny()

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .build(in: core)
        logger.debug("message")

        let logMatcher = try feature.waitAndReturnLogMatchers(count: 1)[0]

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
        core.context = .mockWith(
            dateProvider: RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC(), advancingBySeconds: 1)
        )

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)
        logger.info("message 1")
        logger.info("message 2")
        logger.info("message 3")

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC() })
        logMatchers[1].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1) })
        logMatchers[2].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 2) })
    }

    func testSendingLogsWithDifferentLevels() throws {
        core.context = .mockAny()

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)
        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 6)
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
    }

    func testSendingLogsAboveCertainLevel() throws {
        core.context = .mockAny()

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder
            .set(datadogReportingThreshold: .warn)
            .build(in: core)

        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertStatus(equals: "warn")
        logMatchers[1].assertStatus(equals: "error")
        logMatchers[2].assertStatus(equals: "critical")
    }

    // MARK: - Logging an error

    func testLoggingError() throws {
        core.context = .mockAny()

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        struct TestError: Error {
            var description = "Test description"
        }
        let error = TestError()

        let logger = Logger.builder.build(in: core)
        logger.debug("message", error: error)
        logger.info("message", error: error)
        logger.notice("message", error: error)
        logger.warn("message", error: error)
        logger.error("message", error: error)
        logger.critical("message", error: error)

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 6)
        for matcher in logMatchers {
            matcher.assertValue(forKeyPath: "error.stack", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.message", equals: "TestError(description: \"Test description\")")
            matcher.assertValue(forKeyPath: "error.kind", equals: "TestError")
        }
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        let userInfoProvider = UserInfoProvider()

        core.context = .mockWith(
            userInfoProvider: userInfoProvider
        )

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)

        userInfoProvider.value = .empty
        logger.debug("message with no user info")

        userInfoProvider.value = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        logger.debug("message with user `id` and `name`")

        userInfoProvider.value = UserInfo(
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

        userInfoProvider.value = .empty
        logger.debug("message with no user info")

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 4)
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

        core.context = .mockWith(
            carrierInfoProvider: carrierInfoProvider
        )

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build(in: core)

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

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.name", equals: "Carrier")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.iso_country", equals: "US")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.technology", equals: "LTE")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", equals: true)
        logMatchers[1].assertNoValue(forKeyPath: "network.client.sim_carrier")
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()

        core.context = .mockWith(
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build(in: core)

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

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 2)
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

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)

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

        let logMatcher = try feature.waitAndReturnLogMatchers(count: 1)[0]
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

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)

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

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 3)
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

        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)

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

        let logMatchers = try feature.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertTags(equal: ["tag1", "env:tests", "version:1.2.3"])
        logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd", "env:tests", "version:1.2.3"])
        logMatchers[2].assertTags(equal: ["env:tests", "version:1.2.3"])
    }

    // MARK: - Integration With RUM Feature

    func testGivenBundlingWithRUMEnabledAndRUMMonitorRegistered_whenSendingLog_itContainsCurrentRUMContext() throws {
        core.context = .mockAny()

        let logging: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: logging)

        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        // given
        let logger = Logger.builder.build(in: core)
        Global.rum = RUMMonitor.initialize(in: core)
        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .tap, name: .mockAny())
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        logger.info("info message")

        // then
        let logMatcher = try logging.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.applicationID,
            equals: rum.configuration.applicationID
        )
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.sessionID,
            isTypeOf: String.self
        )
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.viewID,
            isTypeOf: String.self
        )
        logMatcher.assertValue(
            forKeyPath: RUMContextIntegration.Attributes.actionID,
            isTypeOf: String.self
        )
    }

    func testGivenBundlingWithRUMEnabledButRUMMonitorNotRegistered_whenSendingLog_itPrintsWarning() throws {
        core.context = .mockAny()

        let logging: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: logging)

        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        let logger = Logger.builder.build(in: core)
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // when
        logger.info("info message")

        // then
        try XCTAssertTrue(
            XCTUnwrap(dd.logger.warnLog?.message)
                .contains("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Logging will not work.")
        )

        let logMatcher = try logging.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.applicationID)
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.sessionID)
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.viewID)
        logMatcher.assertNoValue(forKeyPath: RUMContextIntegration.Attributes.actionID)
    }

    func testWhenSendingErrorOrCriticalLogs_itCreatesRUMErrorForCurrentView() throws {
        let v1Context: DatadogV1Context = .mockAny()
        core.context = v1Context

        let logging: LoggingFeature = .mockNoOp()
        core.register(feature: logging)

        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
        core.register(feature: rum)

        // given
        let logger = Logger.builder.build(in: core)
        Global.rum = RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                rumFeature: rum,
                crashReportingFeature: nil,
                context: v1Context
            ).replacing(viewUpdatesThrottlerFactory: { NoOpRUMViewUpdatesThrottler() }),
            dateProvider: v1Context.dateProvider
        )
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
        let rumEventMatchers = try rum.waitAndReturnRUMEventMatchers(count: 6)
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
        core.context = .mockAny()

        let logging: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: logging)

        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        // given
        let logger = Logger.builder.build(in: core)
        Global.sharedTracer = Tracer.initialize(configuration: .init(), in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // when
        let span = Global.sharedTracer.startSpan(operationName: "span").setActive()
        logger.info("info message 1")
        span.finish()
        logger.info("info message 2")

        // then
        let logMatchers = try logging.waitAndReturnLogMatchers(count: 2)
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
        core.context = .mockAny()

        let logging: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: logging)

        let tracing: TracingFeature = .mockNoOp()
        core.register(feature: tracing)

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        let logger = Logger.builder.build(in: core)
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // when
        logger.info("info message")

        // then
        try XCTAssertTrue(
            XCTUnwrap(dd.logger.warnLog?.message)
                .contains("Tracing feature is enabled, but no `Tracer` is registered. The Tracing integration with Logging will not work.")
        )

        let logMatcher = try logging.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertNoValue(forKeyPath: LoggingWithActiveSpanIntegration.Attributes.traceID)
        logMatcher.assertNoValue(forKeyPath: LoggingWithActiveSpanIntegration.Attributes.spanID)
    }

    // MARK: - Log Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingLogs_thenLogDateUsesServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        let serverTimeDifference = TimeInterval.random(in: -5..<5).rounded() // few seconds difference

        core.context = .mockWith(
            dateProvider: RelativeDateProvider(using: deviceTime),
            dateCorrector: DateCorrectorMock(offset: serverTimeDifference)
        )

        // When
        let feature: LoggingFeature = .mockByRecordingLogMatchers()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)
        logger.debug("message")

        // Then
        let logMatchers = try feature.waitAndReturnLogMatchers(count: 1)
        logMatchers[0].assertDate { logDate in
            logDate == deviceTime.addingTimeInterval(serverTimeDifference)
        }
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let feature: LoggingFeature = .mockNoOp()
        core.register(feature: feature)

        let logger = Logger.builder.build(in: core)

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
        core.context = nil

        // when
        let logger = Logger.builder.build(in: core)

        // then
        XCTAssertEqual(
            dd.logger.criticalLog?.message,
            "Failed to build `Logger`."
        )
        XCTAssertEqual(
            dd.logger.criticalLog?.error?.message,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        XCTAssertTrue(logger.v2Logger is NOPLogger)
    }

    func testGivenLoggingFeatureDisabled_whenInitializingLogger_itPrintsError() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        core.context = .mockAny()
        XCTAssertNil(core.feature(LoggingFeature.self))

        // when
        let logger = Logger.builder.build(in: core)

        // then
        XCTAssertEqual(
            dd.logger.criticalLog?.message,
            "Failed to build `Logger`."
        )
        XCTAssertEqual(
            dd.logger.criticalLog?.error?.message,
            "🔥 Datadog SDK usage error: `Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
        )
        XCTAssertTrue(logger.v2Logger is NOPLogger)
    }

    func testDDLoggerIsLoggerTypealias() {
        XCTAssertTrue(DDLogger.self == Logger.self)
    }
}
// swiftlint:enable multiline_arguments_brackets
