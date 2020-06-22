/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import OpenTracing
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class DDTracerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Customizing DDTracer

    func testSendingSpanWithDefaultTracer() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationVersion: "1.0.0",
                applicationBundleIdentifier: "com.datadoghq.ios-sdk",
                serviceName: "default-service-name",
                environment: "custom"
            ),
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1)
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation")
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try server.waitAndReturnSpanMatchers(count: 1)[0]
        try spanMatcher.assertItFullyMatches(jsonString: """
        {
          "spans": [
            {
              "trace_id": "1",
              "span_id": "2",
              "parent_id": "0",
              "name": "operation",
              "service": "default-service-name",
              "resource": "operation",
              "start": 1576404000000000000,
              "duration": 500000000,
              "error": 0,
              "type": "custom",
              "meta.tracer.version": "\(sdkVersion)",
              "meta.version": "1.0.0",
              "meta._dd.source": "ios",
              "metrics._top_level": 1,
              "metrics._sampling_priority_v1": 1
            }
          ],
          "env": "custom"
        }
        """) // TOOD: RUMM-422 Network info is not send by default with spans
    }

    func testSendingSpanWithCustomizedTracer() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true
            )
        )

        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        let spanMatcher = try server.waitAndReturnSpanMatchers(count: 1)[0]

        XCTAssertEqual(try spanMatcher.serviceName(), "custom-service-name")
        XCTAssertNoThrow(try spanMatcher.meta.networkAvailableInterfaces())
        XCTAssertNoThrow(try spanMatcher.meta.networkConnectionIsExpensive())
        XCTAssertNoThrow(try spanMatcher.meta.networkReachability())
        XCTAssertNoThrow(try spanMatcher.meta.mobileNetworkCarrierAllowsVoIP())
        XCTAssertNoThrow(try spanMatcher.meta.mobileNetworkCarrierISOCountryCode())
        XCTAssertNoThrow(try spanMatcher.meta.mobileNetworkCarrierName())
        XCTAssertNoThrow(try spanMatcher.meta.mobileNetworkCarrierRadioTechnology())
        XCTAssertNoThrow(try spanMatcher.meta.networkConnectionSupportsIPv4())
        XCTAssertNoThrow(try spanMatcher.meta.networkConnectionSupportsIPv6())
        if #available(iOS 13.0, *) {
            XCTAssertNoThrow(try spanMatcher.meta.networkConnectionIsConstrained())
        }
    }

    // MARK: - Sending Customized Spans

    func testSendingCustomizedSpan() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        let span = tracer.startSpan(
            operationName: "operation",
            tags: [
                "tag1": "string value",
                "error": true,
                DDTags.resource: "GET /foo.png"
            ],
            startTime: .mockDecember15th2019At10AMUTC()
        )
        span.setTag(key: "tag2", value: 123)
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try server.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.resource(), "GET /foo.png")
        XCTAssertEqual(try spanMatcher.startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatcher.duration(), 500_000_000)
        XCTAssertEqual(try spanMatcher.isError(), 1)
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag1"), "string value")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag2"), "123")
    }

    func testSendingSpanWithParentAndBaggageItems() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        let rootSpan = tracer.startSpan(operationName: "root operation")
        let childSpan = tracer.startSpan(operationName: "child operation", childOf: rootSpan.context)
        let grandchildSpan = tracer.startSpan(operationName: "grandchild operation", childOf: childSpan.context)
        rootSpan.setBaggageItem(key: "root-item", value: "foo")
        childSpan.setBaggageItem(key: "child-item", value: "bar")
        grandchildSpan.setBaggageItem(key: "grandchild-item", value: "bizz")

        grandchildSpan.setTag(key: "overwritten", value: "b") // This value "b" coming from a tag...
        grandchildSpan.setBaggageItem(key: "overwritten", value: "a") // ... should overwrite this "a" coming from the baggage item.

        grandchildSpan.finish()
        childSpan.finish()
        rootSpan.finish()

        let spanMatchers = try server.waitAndReturnSpanMatchers(count: 3)
        let rootMatcher = spanMatchers[2]
        let childMatcher = spanMatchers[1]
        let grandchildMatcher = spanMatchers[0]

        // Assert child-parent relationship

        XCTAssertEqual(try grandchildMatcher.operationName(), "grandchild operation")
        XCTAssertEqual(try grandchildMatcher.traceID(), rootSpan.context.dd.traceID.toHexadecimalString)
        XCTAssertEqual(try grandchildMatcher.parentSpanID(), childSpan.context.dd.spanID.toHexadecimalString)
        XCTAssertNil(try? grandchildMatcher.metrics.isRootSpan())
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.child-item"), "bar")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.overwritten"), "b", "Tags should have higher priority than baggage items")

        XCTAssertEqual(try childMatcher.operationName(), "child operation")
        XCTAssertEqual(try childMatcher.traceID(), rootSpan.context.dd.traceID.toHexadecimalString)
        XCTAssertEqual(try childMatcher.parentSpanID(), rootSpan.context.dd.spanID.toHexadecimalString)
        XCTAssertNil(try? childMatcher.metrics.isRootSpan())
        XCTAssertEqual(try childMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertEqual(try childMatcher.meta.custom(keyPath: "meta.child-item"), "bar")
        XCTAssertNil(try? childMatcher.meta.custom(keyPath: "meta.grandchild-item"))

        XCTAssertEqual(try rootMatcher.operationName(), "root operation")
        XCTAssertEqual(try rootMatcher.parentSpanID(), "0")
        XCTAssertEqual(try rootMatcher.metrics.isRootSpan(), 1)
        XCTAssertEqual(try rootMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertNil(try? rootMatcher.meta.custom(keyPath: "meta.child-item"))
        XCTAssertNil(try? rootMatcher.meta.custom(keyPath: "meta.grandchild-item"))

        // Assert timing constraints

        XCTAssertGreaterThan(try grandchildMatcher.startTime(), try childMatcher.startTime())
        XCTAssertGreaterThan(try childMatcher.startTime(), try rootMatcher.startTime())
        XCTAssertLessThan(try grandchildMatcher.duration(), try childMatcher.duration())
        XCTAssertLessThan(try childMatcher.duration(), try rootMatcher.duration())
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        Datadog.instance = Datadog(
            userInfoProvider: UserInfoProvider()
        )
        defer { Datadog.instance = nil }
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            userInfoProvider: Datadog.instance!.userInfoProvider
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: "span with no user info").finish()

        Datadog.setUserInfo(id: "abc-123", name: "Foo")
        tracer.startSpan(operationName: "span with user `id` and `name`").finish()

        Datadog.setUserInfo(id: "abc-123", name: "Foo", email: "foo@example.com")
        tracer.startSpan(operationName: "span with user `id`, `name` and `email`").finish()

        Datadog.setUserInfo(id: nil, name: nil, email: nil)
        tracer.startSpan(operationName: "span with no user info").finish()

        let spanMatchers = try server.waitAndReturnSpanMatchers(count: 4)
        XCTAssertNil(try? spanMatchers[0].meta.userID())
        XCTAssertNil(try? spanMatchers[0].meta.userName())
        XCTAssertNil(try? spanMatchers[0].meta.userEmail())

        XCTAssertEqual(try spanMatchers[1].meta.userID(), "abc-123")
        XCTAssertEqual(try spanMatchers[1].meta.userName(), "Foo")
        XCTAssertNil(try? spanMatchers[1].meta.userEmail())

        XCTAssertEqual(try spanMatchers[2].meta.userID(), "abc-123")
        XCTAssertEqual(try spanMatchers[2].meta.userName(), "Foo")
        XCTAssertEqual(try spanMatchers[2].meta.userEmail(), "foo@example.com")

        XCTAssertNil(try? spanMatchers[3].meta.userID())
        XCTAssertNil(try? spanMatchers[3].meta.userName())
        XCTAssertNil(try? spanMatchers[3].meta.userEmail())
    }

    // MARK: - Sending carrier info

    func testSendingCarrierInfoWhenEnteringAndLeavingCellularServiceRange() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: nil)
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            carrierInfoProvider: carrierInfoProvider
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(
            configuration: .init(sendNetworkInfo: true)
        ).dd

        // simulate entering cellular service range
        carrierInfoProvider.set(
            current: .mockWith(
                carrierName: "Carrier",
                carrierISOCountryCode: "US",
                carrierAllowsVOIP: true,
                radioAccessTechnology: .LTE
            )
        )

        tracer.startSpan(operationName: "span with carrier info").finish()

        // simulate leaving cellular service range
        carrierInfoProvider.set(current: nil)

        tracer.startSpan(operationName: "span with no carrier info").finish()

        let spanMatchers = try server.waitAndReturnSpanMatchers(count: 2)
        XCTAssertEqual(try spanMatchers[0].meta.mobileNetworkCarrierName(), "Carrier")
        XCTAssertEqual(try spanMatchers[0].meta.mobileNetworkCarrierISOCountryCode(), "US")
        XCTAssertEqual(try spanMatchers[0].meta.mobileNetworkCarrierRadioTechnology(), "LTE")
        XCTAssertEqual(try spanMatchers[0].meta.mobileNetworkCarrierAllowsVoIP(), "1")

        XCTAssertNil(try? spanMatchers[1].meta.mobileNetworkCarrierName())
        XCTAssertNil(try? spanMatchers[1].meta.mobileNetworkCarrierISOCountryCode())
        XCTAssertNil(try? spanMatchers[1].meta.mobileNetworkCarrierRadioTechnology())
        XCTAssertNil(try? spanMatchers[1].meta.mobileNetworkCarrierAllowsVoIP())
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(
            configuration: .init(sendNetworkInfo: true)
        ).dd

        // simulate reachable network
        networkConnectionInfoProvider.set(
            current: .mockWith(
                reachability: .yes,
                availableInterfaces: [.wifi, .cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: true
            )
        )

        tracer.startSpan(operationName: "online span").finish()

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

        tracer.startSpan(operationName: "offline span").finish()

        // put the network back online so last span can be send
        networkConnectionInfoProvider.set(current: .mockWith(reachability: .yes))

        let spanMatchers = try server.waitAndReturnSpanMatchers(count: 2)
        XCTAssertEqual(try spanMatchers[0].meta.networkReachability(), "yes")
        XCTAssertEqual(try spanMatchers[0].meta.networkAvailableInterfaces(), "wifi+cellular")
        XCTAssertEqual(try spanMatchers[0].meta.networkConnectionIsConstrained(), "1")
        XCTAssertEqual(try spanMatchers[0].meta.networkConnectionIsExpensive(), "1")
        XCTAssertEqual(try spanMatchers[0].meta.networkConnectionSupportsIPv4(), "1")
        XCTAssertEqual(try spanMatchers[0].meta.networkConnectionSupportsIPv6(), "1")

        XCTAssertEqual(try? spanMatchers[1].meta.networkReachability(), "no")
        XCTAssertNil(try? spanMatchers[1].meta.networkAvailableInterfaces())
        XCTAssertEqual(try spanMatchers[1].meta.networkConnectionIsConstrained(), "0")
        XCTAssertEqual(try spanMatchers[1].meta.networkConnectionIsExpensive(), "0")
        XCTAssertEqual(try spanMatchers[1].meta.networkConnectionSupportsIPv4(), "0")
        XCTAssertEqual(try spanMatchers[1].meta.networkConnectionSupportsIPv6(), "0")
    }

    // MARK: - Sending logs with different network and battery conditions

    func testGivenBadBatteryConditions_itDoesNotTryToSendTraces() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            mobileDevice: .mockWith(
                currentBatteryStatus: { () -> MobileDevice.BatteryStatus in
                    .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                }
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: .mockAny()).finish()

        server.waitAndAssertNoRequestsSent()
    }

    func testGivenNoNetworkConnection_itDoesNotTryToSendTraces() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(reachability: .no)
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: .mockAny()).finish()

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Sending tags

    func testSendingSpanTagsOfDifferentEncodableValues() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        let span = tracer.startSpan(operationName: "operation", tags: [:], startTime: .mockDecember15th2019At10AMUTC())

        // string literal
        span.setTag(key: "string", value: "hello")

        // boolean literal
        span.setTag(key: "bool", value: true)

        // integer literal
        span.setTag(key: "int", value: 10)

        // Typed 8-bit unsigned Integer
        span.setTag(key: "uint-8", value: UInt8(10))

        // double-precision, floating-point value
        span.setTag(key: "double", value: 10.5)

        // array of `Encodable` integer
        span.setTag(key: "array-of-int", value: [1, 2, 3])

        // dictionary of `Encodable` date types
        span.setTag(key: "dictionary-with-date", value: [
            "date": Date.mockDecember15th2019At10AMUTC(),
        ])

        struct Person: Codable {
            let name: String
            let age: Int
            let nationality: String
        }

        // custom `Encodable` structure
        span.setTag(key: "person", value: Person(name: "Adam", age: 30, nationality: "Polish"))

        // nested string literal
        span.setTag(key: "nested.string", value: "hello")

        // URL
        span.setTag(key: "url", value: URL(string: "https://example.com/image.png")!)

        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try server.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.string"), "hello")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.bool"), "true")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.int"), "10")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.uint-8"), "10")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.double"), "10.5")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.array-of-int"), "[1,2,3]")
        XCTAssertEqual(
            try spanMatcher.meta.custom(keyPath: "meta.dictionary-with-date"),
            #"{"date":"2019-12-15T10:00:00.000Z"}"#
        )
        XCTAssertEqual(
            try spanMatcher.meta.custom(keyPath: "meta.person"),
            #"{"name":"Adam","age":30,"nationality":"Polish"}"#
        )
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.nested.string"), "hello")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.url"), "https://example.com/image.png")
    }

    // MARK: - Sending logs

    func testSendingSpanLogs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let loggingFeature = LoggingFeature.mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
        )
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp),
            loggingFeature: loggingFeature
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: ["message": "hello", "custom.field": "value"])

        let logMatcher = try server.waitAndReturnLogMatchers(count: 1)[0]

        logMatcher.assertMessage(equals: "hello")
        logMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        logMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
        logMatcher.assertValue(forKey: "custom.field", equals: "value")
    }

    // MARK: - Injecting span context into carrier

    func testItInjectsSpanContextIntoHTTPHeadersWriter() {
        let tracer: DDTracer = .mockAny()
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = DDHTTPHeadersWriter()
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        let expectedHTTPHeaders = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init())
        var spans: [DDSpan] = []
        let queue = DispatchQueue(label: "spans-array-sync")

        // Start 20 spans concurrently
        DispatchQueue.concurrentPerform(iterations: 20) { iteration in
            let span = tracer.startSpan(operationName: "operation \(iteration)", childOf: nil).dd
            queue.async { spans.append(span) }
        }

        queue.sync {} // wait for all spans in the array

        /// Calls given closures on each span cuncurrently
        func testThreadSafety(closures: [(DDSpan) -> Void]) {
            DispatchQueue.concurrentPerform(iterations: 100) { iteration in
                closures.forEach { closure in
                    closure(spans[iteration % spans.count])
                }
            }
        }

        testThreadSafety(
            closures: [
                // swiftlint:disable opening_brace
                { span in span.setTag(key: .mockRandom(among: "abcde", length: 1), value: "value") },
                { span in span.setBaggageItem(key: .mockRandom(among: "abcde", length: 1), value: "value") },
                { span in _ = span.baggageItem(withKey: .mockRandom(among: "abcde")) },
                { span in _ = span.context.forEachBaggageItem { _, _ in return false } },
                { span in span.log(fields: [.mockRandom(among: "abcde", length: 1): "value"]) },
                { span in span.finish() }
                // swiftlint:enable opening_brace
            ]
        )

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Usage errors

    func testGivenDatadogNotInitialized_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(Datadog.instance)

        // when
        let tracer = DDTracer.initialize(configuration: .init())

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `DDTracer.initialize()`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenTracingFeatureDisabled_whenInitializingTracer_itPrintsError() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableTracing(false)
                .build()
        )

        // when
        let tracer = DDTracer.initialize(configuration: .init())

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `DDTracer.initialize(configuration:)` produces a non-functional tracer, as the tracing feature is disabled."
        )
        XCTAssertTrue(tracer is DDNoopTracer)

        try Datadog.deinitializeOrThrow()
    }

    func testGivenLoggingFeatureDisabled_whenSendingLogFromSpan_itPrintsWarning() throws {
        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableLogging(false)
                .build()
        )

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, dateProvider: SystemDateProvider(), identifier: "sdk-user")

        // when
        let tracer = DDTracer.initialize(configuration: .init())
        let span = tracer.startSpan(operationName: "foo")
        span.log(fields: ["bar": "bizz"])

        // then
        XCTAssertEqual(output.recordedLog?.level, .warn)
        XCTAssertEqual(output.recordedLog?.message, "The log for span \"foo\" will not be send, because the Logging feature is disabled.")

        try Datadog.deinitializeOrThrow()
    }
}
// swiftlint:enable multiline_arguments_brackets
