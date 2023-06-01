/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class TracerTests: XCTestCase {
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

    // MARK: - Customizing Tracer

    func testSendingSpanWithDefaultTracer() throws {
        core.context = .mockWith(
            service: "default-service-name",
            env: "custom",
            version: "1.0.0",
            source: "abc",
            sdkVersion: "1.2.3",
            ciAppOrigin: nil,
            applicationBundleIdentifier: "com.datadoghq.ios-sdk"
        )

        let feature: TracingFeature = .mockWith(
            configuration: .mockWith(
                uuidGenerator: RelativeTracingUUIDGenerator(startingFrom: 1),
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            )
        )
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: "operation")
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        try spanMatcher.assertItFullyMatches(jsonString: """
        {
          "spans": [
            {
              "_dd.agent_psr": 1,
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
              "meta.tracer.version": "1.2.3",
              "meta.version": "1.0.0",
              "meta._dd.source": "abc",
              "metrics._top_level": 1,
              "metrics._sampling_priority_v1": 1
            }
          ],
          "env": "custom"
        }
        """)
    }

    func testSendingSpanWithCustomizedTracer() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true
            ),
            in: core
        )

        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
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

    func testSendingSpanWithGlobalTags() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                globalTags: [
                    "globaltag1": "globalValue1",
                    "globaltag2": "globalValue2"
                ]
            ),
            in: core
        )

        let span = tracer.startSpan(operationName: .mockAny())
        span.setTag(key: "globaltag2", value: "overwrittenValue" )
        span.finish()

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        XCTAssertEqual(try spanMatcher.serviceName(), "custom-service-name")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag1"), "globalValue1")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag2"), "overwrittenValue")
    }

    // MARK: - Tracer with sampling rate

    func testUsingSamplingRate() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(samplingRate: 42), in: core).dd

        let span = tracer.startSpan(
            operationName: "operation",
            startTime: .mockDecember15th2019At10AMUTC()
        )
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatcher.duration(), 500_000_000)
        XCTAssertEqual(try spanMatcher.dd.samplingRate(), 0.42)
    }

    // MARK: - Sending Customized Spans

    func testSendingCustomizedSpan() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

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

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.resource(), "GET /foo.png")
        XCTAssertEqual(try spanMatcher.startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatcher.duration(), 500_000_000)
        XCTAssertEqual(try spanMatcher.isError(), 1)
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag1"), "string value")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag2"), "123")
    }

    func testSendingSpanWithParentAndBaggageItems() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

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

        let spanMatchers = try core.waitAndReturnSpanMatchers()
        let rootMatcher = spanMatchers[2]
        let childMatcher = spanMatchers[1]
        let grandchildMatcher = spanMatchers[0]

        // Assert child-parent relationship

        XCTAssertEqual(try grandchildMatcher.operationName(), "grandchild operation")
        XCTAssertEqual(try grandchildMatcher.traceID(), rootSpan.context.dd.traceID.toString(.hexadecimal))
        XCTAssertEqual(try grandchildMatcher.parentSpanID(), childSpan.context.dd.spanID.toString(.hexadecimal))
        XCTAssertNil(try? grandchildMatcher.metrics.isRootSpan())
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.child-item"), "bar")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.overwritten"), "b", "Tags should have higher priority than baggage items")

        XCTAssertEqual(try childMatcher.operationName(), "child operation")
        XCTAssertEqual(try childMatcher.traceID(), rootSpan.context.dd.traceID.toString(.hexadecimal))
        XCTAssertEqual(try childMatcher.parentSpanID(), rootSpan.context.dd.spanID.toString(.hexadecimal))
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

    func testSendingSpanWithActiveSpanAsAParent() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd
        let queue1 = DispatchQueue(label: "\(#function)-queue1")
        let queue2 = DispatchQueue(label: "\(#function)-queue2")

        let rootSpan = tracer.startSpan(operationName: "root operation").setActive()

        queue1.sync {
            let child1Span = tracer.startSpan(operationName: "child 1 operation")
            child1Span.finish()
        }

        queue2.sync {
            let child2Span = tracer.startSpan(operationName: "child 2 operation")
            child2Span.finish()
        }

        rootSpan.finish()

        let spanMatchers = try core.waitAndReturnSpanMatchers()
        let rootMatcher = spanMatchers[2]
        let child1Matcher = spanMatchers[1]
        let child2Matcher = spanMatchers[0]

        XCTAssertEqual(try rootMatcher.parentSpanID(), "0")
        XCTAssertEqual(try child1Matcher.parentSpanID(), try rootMatcher.spanID())
        XCTAssertEqual(try child2Matcher.parentSpanID(), try rootMatcher.spanID())
    }

    func testSendingSpansWithNoParent() throws {
        let expectation = self.expectation(description: "Complete 2 fake API requests")
        expectation.expectedFulfillmentCount = 2

        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd
        let queue = DispatchQueue(label: "\(#function)-queue")

        func makeAPIRequest(completion: @escaping () -> Void) {
            queue.asyncAfter(deadline: .now() + 0.1) {
                completion()
                expectation.fulfill()
            }
        }

        let request1Span = tracer.startSpan(operationName: "/resource/1")
        makeAPIRequest {
            request1Span.finish()
        }

        let request2Span = tracer.startSpan(operationName: "/resource/2")
        makeAPIRequest {
            request2Span.finish()
        }
        tracer.activeSpan?.finish()

        waitForExpectations(timeout: 5)
        let spanMatchers = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), "0")
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), "0")
    }

    func testStartingRootActiveSpanInAsynchronousJobs() throws {
        let expectation = self.expectation(description: "Complete 2 fake API requests")
        expectation.expectedFulfillmentCount = 2

        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core)
        let queue = DispatchQueue(label: "\(#function)")

        func makeFakeAPIRequest(on queue: DispatchQueue, completion: @escaping () -> Void) {
            let requestSpan = tracer.startRootSpan(operationName: "request").setActive()
            queue.asyncAfter(deadline: .now() + 0.1) {
                let responseDecodingSpan = tracer.startSpan(operationName: "response decoding")
                responseDecodingSpan.finish()
                requestSpan.finish()
                completion()
                expectation.fulfill()
            }
        }
        makeFakeAPIRequest(on: queue) {}
        makeFakeAPIRequest(on: queue) {}

        waitForExpectations(timeout: 5)
        let spanMatchers = try core.waitAndReturnSpanMatchers()
        let response1Matcher = spanMatchers[0]
        let request1Matcher = spanMatchers[1]
        let response2Matcher = spanMatchers[2]
        let request2Matcher = spanMatchers[3]

        XCTAssertEqual(try response1Matcher.parentSpanID(), try request1Matcher.spanID())
        XCTAssertEqual(try request1Matcher.parentSpanID(), "0")
        XCTAssertEqual(try response2Matcher.parentSpanID(), try request2Matcher.spanID())
        XCTAssertEqual(try request2Matcher.parentSpanID(), "0")
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        core.context = .mockWith(
            userInfo: .empty
        )

        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

        tracer.startSpan(operationName: "span with no user info").finish()
        tracer.queue.sync {} // wait for processing the span event in `DDSpan`

        core.context.userInfo = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        tracer.startSpan(operationName: "span with user `id` and `name`").finish()
        tracer.queue.sync {}

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
        tracer.startSpan(operationName: "span with user `id`, `name`, `email` and `extraInfo`").finish()
        tracer.queue.sync {}

        core.context.userInfo = .empty
        tracer.startSpan(operationName: "span with no user info").finish()

        let spanMatchers = try core.waitAndReturnSpanMatchers()
        XCTAssertNil(try? spanMatchers[0].meta.userID())
        XCTAssertNil(try? spanMatchers[0].meta.userName())
        XCTAssertNil(try? spanMatchers[0].meta.userEmail())

        XCTAssertEqual(try spanMatchers[1].meta.userID(), "abc-123")
        XCTAssertEqual(try spanMatchers[1].meta.userName(), "Foo")
        XCTAssertNil(try? spanMatchers[1].meta.userEmail())

        XCTAssertEqual(try spanMatchers[2].meta.userID(), "abc-123")
        XCTAssertEqual(try spanMatchers[2].meta.userName(), "Foo")
        XCTAssertEqual(try spanMatchers[2].meta.userEmail(), "foo@example.com")
        XCTAssertEqual(try spanMatchers[2].meta.custom(keyPath: "meta.usr.str"), "value")
        XCTAssertEqual(try spanMatchers[2].meta.custom(keyPath: "meta.usr.int"), "11235")
        XCTAssertEqual(try spanMatchers[2].meta.custom(keyPath: "meta.usr.bool"), "true")

        XCTAssertNil(try? spanMatchers[3].meta.userID())
        XCTAssertNil(try? spanMatchers[3].meta.userName())
        XCTAssertNil(try? spanMatchers[3].meta.userEmail())
    }

    // MARK: - Sending carrier info

    func testSendingCarrierInfoWhenEnteringAndLeavingCellularServiceRange() throws {
        core.context = .mockWith(
            carrierInfo: nil
        )

        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(
            configuration: .init(sendNetworkInfo: true),
            in: core
        ).dd

        // simulate entering cellular service range
        core.context.carrierInfo = .mockWith(
            carrierName: "Carrier",
            carrierISOCountryCode: "US",
            carrierAllowsVOIP: true,
            radioAccessTechnology: .LTE
        )

        tracer.startSpan(operationName: "span with carrier info").finish()
        tracer.queue.sync {} // wait for processing the span event in `DDSpan`

        // simulate leaving cellular service range
        core.context.carrierInfo = nil

        tracer.startSpan(operationName: "span with no carrier info").finish()

        let spanMatchers = try core.waitAndReturnSpanMatchers()
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
        core.context = .mockWith(networkConnectionInfo: nil)

        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(
            configuration: .init(sendNetworkInfo: true),
            in: core
        ).dd

        // simulate reachable network
        core.context.networkConnectionInfo = .mockWith(
            reachability: .yes,
            availableInterfaces: [.wifi, .cellular],
            supportsIPv4: true,
            supportsIPv6: true,
            isExpensive: true,
            isConstrained: true
        )

        tracer.startSpan(operationName: "online span").finish()
        tracer.queue.sync {} // wait for processing the span event in `DDSpan`

        // simulate unreachable network
        core.context.networkConnectionInfo = .mockWith(
            reachability: .no,
            availableInterfaces: [],
            supportsIPv4: false,
            supportsIPv6: false,
            isExpensive: false,
            isConstrained: false
        )

        tracer.startSpan(operationName: "offline span").finish()

        let spanMatchers = try core.waitAndReturnSpanMatchers()
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

    // MARK: - Sending tags

    func testSendingSpanTagsOfDifferentEncodableValues() throws {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core).dd

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

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
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

    // MARK: - Integration With Logging Feature

    func testSendingSpanLogs() throws {
        let logging: LoggingFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.register(feature: logging)

        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.log(fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error", OTLogFields.message: "Ops!"])

        let logMatchers = try core.waitAndReturnLogMatchers()

        let regularLogMatcher = logMatchers[0]
        let errorLogMatcher = logMatchers[1]

        regularLogMatcher.assertStatus(equals: "info")
        regularLogMatcher.assertMessage(equals: "hello")
        regularLogMatcher.assertValue(forKey: "dd.trace_id", equals: span.context.dd.traceID.toString(.decimal))
        regularLogMatcher.assertValue(forKey: "dd.span_id", equals: span.context.dd.spanID.toString(.decimal))
        regularLogMatcher.assertValue(forKey: "custom.field", equals: "value")

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertValue(forKey: "error.message", equals: "Ops!")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: span.context.dd.traceID.toString(.decimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: span.context.dd.spanID.toString(.decimal))
    }

    func testSendingSpanLogsWithErrorFromArguments() throws {
        let logging: LoggingFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.register(feature: logging)

        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.setError(kind: "Swift error", message: "Ops!")

        let logMatchers = try core.waitAndReturnLogMatchers()
        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertValue(forKey: "error.message", equals: "Ops!")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: span.context.dd.traceID.toString(.decimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: span.context.dd.spanID.toString(.decimal))
    }

    func testSendingSpanLogsWithErrorFromNSError() throws {
        let logging: LoggingFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.register(feature: logging)

        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        let error = NSError(
            domain: "Tracer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Ops!"]
        )
        span.setError(error)

        let logMatchers = try core.waitAndReturnLogMatchers()

        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Tracer - 1")
        errorLogMatcher.assertValue(forKey: "error.message", equals: "Ops!")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: span.context.dd.traceID.toString(.decimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: span.context.dd.spanID.toString(.decimal))
    }

    func testSendingSpanLogsWithErrorFromSwiftError() throws {
        let logging: LoggingFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        core.register(feature: logging)

        let tracing: TracingFeature = .mockAny()
        core.register(feature: tracing)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.setError(ErrorMock("Ops!"))

        let logMatchers = try core.waitAndReturnLogMatchers()

        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "ErrorMock")
        errorLogMatcher.assertValue(forKey: "error.message", equals: "Ops!")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: span.context.dd.traceID.toString(.decimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: span.context.dd.spanID.toString(.decimal))
    }

    // MARK: - Integration With RUM Feature
//    // TODO: RUMM-2843 [V2 regression] RUM context is not associated with span started on caller thread
//    func testGivenBundlingWithRUMEnabledAndRUMMonitorRegistered_whenSendingSpanBeforeAnyUserActivity_itContainsSessionId() throws {
//        let tracing: TracingFeature = .mockAny()
//        core.register(feature: tracing)
//
//        let rum: RUMFeature = .mockAny()
//        core.register(feature: rum)
//
//        // given
//        Global.sharedTracer = Tracer.initialize(configuration: .init(), in: core).dd
//        defer { Global.sharedTracer = DDNoopTracer() }
//        Global.rum = RUMMonitor.initialize(in: core)
//        defer { Global.rum = DDNoopRUMMonitor() }
//
//        // when
//        let span = Global.sharedTracer.startSpan(operationName: "operation", tags: [:], startTime: Date())
//        span.finish()
//
//        // then
//        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
//        XCTAssertValidRumUUID(try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextAttributes.IDs.sessionID)"))
//    }

    // TODO: RUMM-2843 [V2 regression] RUM context is not associated with span started on caller thread
//    func testGivenBundlingWithRUMEnabledAndRUMMonitorRegistered_whenSendingSpan_itContainsCurrentRUMContext() throws {
//        let tracing: TracingFeature = .mockAny()
//        core.register(feature: tracing)
//
//        let rum: RUMFeature = .mockAny()
//        core.register(feature: rum)
//
//        // given
//        Global.sharedTracer = Tracer.initialize(configuration: .init(), in: core).dd
//        defer { Global.sharedTracer = DDNoopTracer() }
//        Global.rum = RUMMonitor.initialize(in: core)
//        Global.rum.startView(viewController: mockView)
//        defer { Global.rum = DDNoopRUMMonitor() }
//
//        // when
//        let span = Global.sharedTracer.startSpan(operationName: "operation", tags: [:], startTime: Date())
//        span.finish()
//
//        // then
//        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
//        XCTAssertEqual(
//            try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextAttributes.IDs.applicationID)"),
//            rum.configuration.applicationID
//        )
//        XCTAssertValidRumUUID(try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextAttributes.IDs.sessionID)"))
//        XCTAssertValidRumUUID(try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextAttributes.IDs.viewID)"))
//    }

    // MARK: - Injecting span context into carrier

    func testItInjectsSpanContextWithHTTPHeadersWriter() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext1 = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())
        let spanContext2 = DDSpanContext(traceID: 3, spanID: 4, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = HTTPHeadersWriter(sampler: .mockKeepAll())
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext1, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders1 = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
            "x-datadog-sampling-priority": "1",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders1)

        // When
        tracer.inject(spanContext: spanContext2, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders2 = [
            "x-datadog-trace-id": "3",
            "x-datadog-parent-id": "4",
            "x-datadog-sampling-priority": "1",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders2)
    }

    func testItInjectsSpanContextWithOTelHTTPHeadersWriter_usingMultipleHeaders() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext1 = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())
        let spanContext2 = DDSpanContext(traceID: 4, spanID: 5, parentSpanID: 6, baggageItems: .mockAny())
        let spanContext3 = DDSpanContext(traceID: 77, spanID: 88, parentSpanID: nil, baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .multiple)
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext1, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders1 = [
            "X-B3-TraceId": "00000000000000000000000000000001",
            "X-B3-SpanId": "0000000000000002",
            "X-B3-Sampled": "1",
            "X-B3-ParentSpanId": "0000000000000003"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders1)

        // When
        tracer.inject(spanContext: spanContext2, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders2 = [
            "X-B3-TraceId": "00000000000000000000000000000004",
            "X-B3-SpanId": "0000000000000005",
            "X-B3-Sampled": "1",
            "X-B3-ParentSpanId": "0000000000000006"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders2)

        // When
        tracer.inject(spanContext: spanContext3, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders3 = [
            "X-B3-TraceId": "0000000000000000000000000000004d",
            "X-B3-SpanId": "0000000000000058",
            "X-B3-Sampled": "1"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders3)
    }

    func testItInjectsSpanContextWithOTelHTTPHeadersWriter_usingSingleHeader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext1 = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())
        let spanContext2 = DDSpanContext(traceID: 4, spanID: 5, parentSpanID: 6, baggageItems: .mockAny())
        let spanContext3 = DDSpanContext(traceID: 77, spanID: 88, parentSpanID: nil, baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .single)
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext1, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders1 = [
            "b3": "00000000000000000000000000000001-0000000000000002-1-0000000000000003"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders1)

        // When
        tracer.inject(spanContext: spanContext2, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders2 = [
            "b3": "00000000000000000000000000000004-0000000000000005-1-0000000000000006"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders2)

        // When
        tracer.inject(spanContext: spanContext3, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders3 = [
            "b3": "0000000000000000000000000000004d-0000000000000058-1"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders3)
    }

    func testItInjectsRejectedSpanContextWithOTelHTTPHeadersWriter_usingSingleHeader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockRejectAll())
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders = [
            "b3": "0"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testItInjectsRejectedSpanContextWithOTelHTTPHeadersWriter_usingMultipleHeader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockRejectAll(), injectEncoding: .multiple)
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders = [
            "X-B3-Sampled": "0"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testItInjectsSpanContextWithW3CHTTPHeadersWriter() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext1 = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())
        let spanContext2 = DDSpanContext(traceID: 4, spanID: 5, parentSpanID: 6, baggageItems: .mockAny())
        let spanContext3 = DDSpanContext(traceID: 77, spanID: 88, parentSpanID: nil, baggageItems: .mockAny())

        let httpHeadersWriter = W3CHTTPHeadersWriter(sampler: .mockKeepAll())
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext1, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders1 = [
            "traceparent": "00-00000000000000000000000000000001-0000000000000002-01"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders1)

        // When
        tracer.inject(spanContext: spanContext2, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders2 = [
            "traceparent": "00-00000000000000000000000000000004-0000000000000005-01"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders2)

        // When
        tracer.inject(spanContext: spanContext3, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders3 = [
            "traceparent": "00-0000000000000000000000000000004d-0000000000000058-01"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders3)
    }

    func testItInjectsRejectedSpanContextWithW3CHTTPHeadersWriter() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = W3CHTTPHeadersWriter(sampler: .mockRejectAll())
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders = [
            "traceparent": "00-00000000000000000000000000000001-0000000000000002-00"
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testItInjectsRejectedSpanContextWithHTTPHeadersWriter() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = HTTPHeadersWriter(sampler: .mockRejectAll())
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        // When
        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        // Then
        let expectedHTTPHeaders = [
            "x-datadog-sampling-priority": "0",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testItExtractsSpanContextWithHTTPHeadersReader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let injectedSpanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = HTTPHeadersWriter(sampler: .mockKeepAll())
        tracer.inject(spanContext: injectedSpanContext, writer: httpHeadersWriter)

        let httpHeadersReader = HTTPHeadersReader(
            httpHeaderFields: httpHeadersWriter.tracePropagationHTTPHeaders
        )
        let extractedSpanContext = tracer.extract(reader: httpHeadersReader)

        XCTAssertEqual(extractedSpanContext?.dd.traceID, injectedSpanContext.dd.traceID)
        XCTAssertEqual(extractedSpanContext?.dd.spanID, injectedSpanContext.dd.spanID)
        XCTAssertNil(extractedSpanContext?.dd.parentSpanID)
    }

    func testItExtractsSpanContextWithOTelHTTPHeadersReader_forMultipleHeaders() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let injectedSpanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .multiple)
        tracer.inject(spanContext: injectedSpanContext, writer: httpHeadersWriter)

        let httpHeadersReader = OTelHTTPHeadersReader(
            httpHeaderFields: httpHeadersWriter.tracePropagationHTTPHeaders
        )
        let extractedSpanContext = tracer.extract(reader: httpHeadersReader)

        XCTAssertEqual(extractedSpanContext?.dd.traceID, injectedSpanContext.dd.traceID)
        XCTAssertEqual(extractedSpanContext?.dd.spanID, injectedSpanContext.dd.spanID)
        XCTAssertEqual(extractedSpanContext?.dd.parentSpanID, injectedSpanContext.dd.parentSpanID)
    }

    func testItExtractsSpanContextWithOTelHTTPHeadersReader_forSingleHeader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let injectedSpanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())

        let httpHeadersWriter = OTelHTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .single)
        tracer.inject(spanContext: injectedSpanContext, writer: httpHeadersWriter)

        let httpHeadersReader = OTelHTTPHeadersReader(
            httpHeaderFields: httpHeadersWriter.tracePropagationHTTPHeaders
        )
        let extractedSpanContext = tracer.extract(reader: httpHeadersReader)

        XCTAssertEqual(extractedSpanContext?.dd.traceID, injectedSpanContext.dd.traceID)
        XCTAssertEqual(extractedSpanContext?.dd.spanID, injectedSpanContext.dd.spanID)
        XCTAssertEqual(extractedSpanContext?.dd.parentSpanID, injectedSpanContext.dd.parentSpanID)
    }

    func testItExtractsSpanContextWithW3CHTTPHeadersReader() {
        let tracer: Tracer = .mockAny(in: PassthroughCoreMock())
        let injectedSpanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: 3, baggageItems: .mockAny())

        let httpHeadersWriter = W3CHTTPHeadersWriter(sampler: .mockKeepAll())
        tracer.inject(spanContext: injectedSpanContext, writer: httpHeadersWriter)

        let httpHeadersReader = W3CHTTPHeadersReader(
            httpHeaderFields: httpHeadersWriter.tracePropagationHTTPHeaders
        )
        let extractedSpanContext = tracer.extract(reader: httpHeadersReader)

        XCTAssertEqual(extractedSpanContext?.dd.traceID, injectedSpanContext.dd.traceID)
        XCTAssertEqual(extractedSpanContext?.dd.spanID, injectedSpanContext.dd.spanID)
        XCTAssertNil(extractedSpanContext?.dd.parentSpanID)
    }

    // MARK: - Span Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingSpans_thenSpanDateUsesServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        let serverTimeOffset = TimeInterval.random(in: -5..<5).rounded() // few seconds difference

        core.context = .mockWith(
            serverTimeOffset: serverTimeOffset
        )

        // When
        let feature: TracingFeature = .mockWith(
            configuration: .mockWith(dateProvider: RelativeDateProvider(using: deviceTime))
        )
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core)

        let span = tracer.startSpan(operationName: .mockAny())
        span.finish(at: deviceTime.addingTimeInterval(2)) // 2 seconds long span

        // Then
        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        XCTAssertEqual(
            try spanMatcher.startTime(),
            deviceTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toNanoseconds,
            "The `startTime` should be using server time."
        )
        XCTAssertEqual(
            try spanMatcher.duration(),
            2_000_000_000,
            "The `duration` should remain unaffected."
        )
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let feature: TracingFeature = .mockAny()
        core.register(feature: feature)

        let tracer = Tracer.initialize(configuration: .init(), in: core)
        var spans: [DDSpan] = []
        let queue = DispatchQueue(label: "spans-array-sync")

        // Start 20 spans concurrently
        DispatchQueue.concurrentPerform(iterations: 20) { iteration in
            let span = tracer.startSpan(operationName: "operation \(iteration)", childOf: nil).dd
            queue.async { spans.append(span) }
        }

        queue.sync {} // wait for all spans in the array

        /// Calls given closures on each span concurrently
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
                { span in span.setTag(key: .mockRandom(among: .alphanumerics, length: 1), value: "value") },
                { span in span.setBaggageItem(key: .mockRandom(among: .alphanumerics, length: 1), value: "value") },
                { span in _ = span.baggageItem(withKey: .mockRandom(among: .alphanumerics)) },
                { span in _ = span.context.forEachBaggageItem { _, _ in return false } },
                { span in span.log(fields: [.mockRandom(among: .alphanumerics, length: 1): "value"]) },
                { span in span.finish() }
                // swiftlint:enable opening_brace
            ]
        )
    }

    // MARK: - Usage errors

    func testGivenDatadogNotInitialized_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        let core = NOPDatadogCore()

        // when
        let tracer = Tracer.initialize(configuration: .init(), in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Tracer.initialize()`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenTracingFeatureDisabled_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableTracing(false)
                .build()
        )

        // when
        let tracer = Tracer.initialize(configuration: .init())

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Tracer.initialize(configuration:)` produces a non-functional tracer, as the tracing feature is disabled."
        )
        XCTAssertTrue(tracer is DDNoopTracer)

        Datadog.flushAndDeinitialize()
    }

    func testGivenLoggingFeatureNotRegistered_whenSendingLogFromSpan_itPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        XCTAssertNil(core.feature(LoggingFeature.self))
        core.register(feature: TracingFeature.mockAny())

        // when
        let tracer = Tracer.initialize(configuration: .init(), in: core)
        let span = tracer.startSpan(operationName: "foo")
        span.log(fields: ["bar": "bizz"])

        // then
        core.flush()
        XCTAssertEqual(dd.logger.warnLog?.message, "The log for span \"foo\" will not be send, because the Logging feature is disabled.")
    }

    func testGivenTracerInitialized_whenInitializingAnotherTime_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration.builderUsing(clientToken: .mockAny(), environment: .mockAny()).build()
        )
        Global.sharedTracer = Tracer.initialize(configuration: .init())
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // when
        _ = Tracer.initialize(configuration: .init())

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: The `Tracer` instance was already created. Use existing `Global.sharedTracer` instead of initializing the `Tracer` another time.
            """
        )

        Datadog.flushAndDeinitialize()
    }

    func testGivenOnlyTracingAutoInstrumentationEnabled_whenTracerIsNotRegistered_itPrintsWarningsOnEachFirstPartyRequest() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration
                .builderUsing(clientToken: .mockAny(), environment: .mockAny())
                .trackURLSession(firstPartyHosts: [.mockAny()])
                .build()
        )
        defer { Datadog.flushAndDeinitialize() }

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let instrumentation = defaultDatadogCore.v1.feature(URLSessionAutoInstrumentation.self)
        let tracingHandler = try XCTUnwrap(instrumentation?.interceptor.handler)

        // When
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // Then
        tracingHandler.notify_taskInterceptionCompleted(interception: TaskInterception(request: .mockAny(), isFirstParty: true))
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            `URLSession` request was completed, but no `Tracer` is registered on `Global.sharedTracer`. Tracing auto instrumentation will not work.
            Make sure `Global.sharedTracer = Tracer.initialize()` is called before any network request is send.
            """
        )
    }
}
// swiftlint:enable multiline_arguments_brackets
