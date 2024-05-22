/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace
@testable import DatadogLogs
@testable import DatadogCore
@testable import DatadogRUM

// swiftlint:disable multiline_arguments_brackets
class TracerTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: Trace.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        config = Trace.Configuration()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        config = nil
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
        config.dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        config.traceIDGenerator = RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100))
        config.spanIDGenerator = RelativeSpanIDGenerator(startingFrom: 100)

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

        let span = tracer.startSpan(operationName: "operation")
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        try spanMatcher.assertItFullyMatches(jsonString: """
        {
          "spans": [
            {
              "_dd.agent_psr": 1,
              "trace_id": "64",
              "span_id": "64",
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
              "metrics._sampling_priority_v1": 1,
              "meta._dd.p.tid": "a"
            }
          ],
          "env": "custom"
        }
        """)
    }

    func testSendingSpanWithCustomizedTracer() throws {
        config.service = "custom-service-name"
        config.networkInfoEnabled = true

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        config.service = "custom-service-name"
        config.tags = [
            "globaltag1": "globalValue1",
            "globaltag2": "globalValue2"
        ]

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

        let span = tracer.startSpan(operationName: .mockAny())
        span.setTag(key: "globaltag2", value: "overwrittenValue" )
        span.finish()

        let spanMatcher = try core.waitAndReturnSpanMatchers()[0]
        XCTAssertEqual(try spanMatcher.serviceName(), "custom-service-name")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag1"), "globalValue1")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag2"), "overwrittenValue")
    }

    // MARK: - Sending Customized Spans

    func testSendingCustomizedSpan() throws {
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

        let span = tracer.startSpan(
            operationName: "operation",
            tags: [
                "tag1": "string value",
                "error": true,
                SpanTags.resource: "GET /foo.png"
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
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        XCTAssertEqual(try grandchildMatcher.traceID(), rootSpan.context.dd.traceID)
        XCTAssertEqual(try grandchildMatcher.parentSpanID(), childSpan.context.dd.spanID)
        XCTAssertNil(try? grandchildMatcher.metrics.isRootSpan())
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.child-item"), "bar")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.grandchild-item"), "bizz")
        XCTAssertEqual(try grandchildMatcher.meta.custom(keyPath: "meta.overwritten"), "b", "Tags should have higher priority than baggage items")

        XCTAssertEqual(try childMatcher.operationName(), "child operation")
        XCTAssertEqual(try childMatcher.traceID(), rootSpan.context.dd.traceID)
        XCTAssertEqual(try childMatcher.parentSpanID(), rootSpan.context.dd.spanID)
        XCTAssertNil(try? childMatcher.metrics.isRootSpan())
        XCTAssertEqual(try childMatcher.meta.custom(keyPath: "meta.root-item"), "foo")
        XCTAssertEqual(try childMatcher.meta.custom(keyPath: "meta.child-item"), "bar")
        XCTAssertNil(try? childMatcher.meta.custom(keyPath: "meta.grandchild-item"))

        XCTAssertEqual(try rootMatcher.operationName(), "root operation")
        XCTAssertEqual(try rootMatcher.parentSpanID(), .invalid)
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
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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

        XCTAssertEqual(try rootMatcher.parentSpanID(), .invalid)
        XCTAssertEqual(try child1Matcher.parentSpanID(), try rootMatcher.spanID())
        XCTAssertEqual(try child2Matcher.parentSpanID(), try rootMatcher.spanID())
    }

    func testSendingSpansWithNoParent() throws {
        let expectation = self.expectation(description: "Complete 2 fake API requests")
        expectation.expectedFulfillmentCount = 2

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
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
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), .invalid)
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), .invalid)
    }

    func testStartingRootActiveSpanInAsynchronousJobs() throws {
        let expectation = self.expectation(description: "Complete 2 fake API requests")
        expectation.expectedFulfillmentCount = 2

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
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
        XCTAssertEqual(try request1Matcher.parentSpanID(), .invalid)
        XCTAssertEqual(try response2Matcher.parentSpanID(), try request2Matcher.spanID())
        XCTAssertEqual(try request2Matcher.parentSpanID(), .invalid)
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        core.context = .mockWith(
            userInfo: .empty
        )

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core).dd

        tracer.startSpan(operationName: "span with no user info").finish()

        core.context.userInfo = UserInfo(id: "abc-123", name: "Foo", email: nil, extraInfo: [:])
        tracer.startSpan(operationName: "span with user `id` and `name`").finish()

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

        config.networkInfoEnabled = true
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core).dd

        // simulate entering cellular service range
        core.context.carrierInfo = .mockWith(
            carrierName: "Carrier",
            carrierISOCountryCode: "US",
            carrierAllowsVOIP: true,
            radioAccessTechnology: .LTE
        )

        tracer.startSpan(operationName: "span with carrier info").finish()

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

        config.networkInfoEnabled = true
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core).dd

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
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
        tracer.dd.spanEventBuilder.attributesEncoder.outputFormatting = [.sortedKeys]

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
            #"{"age":30,"name":"Adam","nationality":"Polish"}"#
        )
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.nested.string"), "hello")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.url"), "https://example.com/image.png")
    }

    // MARK: - Integration With Logging Feature

    func testSendingSpanLogs() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.log(fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error", OTLogFields.message: "Ops!"])

        let logMatchers = try core.waitAndReturnLogMatchers()

        let regularLogMatcher = logMatchers[0]
        let errorLogMatcher = logMatchers[1]

        regularLogMatcher.assertStatus(equals: "info")
        regularLogMatcher.assertMessage(equals: "hello")
        regularLogMatcher.assertValue(forKey: "dd.trace_id", equals: String(span.context.dd.traceID, representation: .hexadecimal))
        regularLogMatcher.assertValue(forKey: "dd.span_id", equals: String(span.context.dd.spanID, representation: .hexadecimal))
        regularLogMatcher.assertValue(forKey: "custom.field", equals: "value")

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertValue(forKey: "error.message", equals: "Ops!")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: String(span.context.dd.traceID, representation: .hexadecimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: String(span.context.dd.spanID, representation: .hexadecimal))
    }

    func testSendingSpanLogsWithErrorFromArguments() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: String(span.context.dd.traceID, representation: .hexadecimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: String(span.context.dd.spanID, representation: .hexadecimal))
    }

    func testSendingSpanLogsWithErrorFromNSError() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: String(span.context.dd.traceID, representation: .hexadecimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: String(span.context.dd.spanID, representation: .hexadecimal))
    }

    func testSendingSpanLogsWithErrorFromSwiftError() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: String(span.context.dd.traceID, representation: .hexadecimal))
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: String(span.context.dd.spanID, representation: .hexadecimal))
    }

    // MARK: - Integration With RUM Feature

    func testGivenBundleWithRumEnabled_whenSendingSpanBeforeAnyInteraction_itContainsViewId() throws {
        config.bundleWithRumEnabled = true
        Trace.enable(with: config, in: core)

        // Given
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "operation")
        span.finish()

        // Then
        let rumEvent = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMViewEvent.self).last)
        let spanEvent = try XCTUnwrap(core.waitAndReturnSpanEvents().first)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumApplicationID], "rum-app-id")
        XCTAssertEqual(spanEvent.tags[SpanTags.rumSessionID], rumEvent.session.id)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumViewID], rumEvent.view.id)
        XCTAssertNil(spanEvent.tags[SpanTags.rumActionID])
    }

    func testGivenBundleWithRumEnabled_whenStartingSpanWhileUserInteractionIsPending_itContainsActionId() throws {
        config.bundleWithRumEnabled = true
        Trace.enable(with: config, in: core)

        // Given
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)

        // When
        RUMMonitor.shared(in: core).startAction(type: .swipe, name: "swipe")
        let span = Tracer.shared(in: core).startSpan(operationName: "operation")
        RUMMonitor.shared(in: core).stopAction(type: .swipe, name: "swipe")
        span.finish()

        // Then
        let rumEvent = try XCTUnwrap(
            core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMActionEvent.self).first(where: { $0.action.type == .swipe })
        )
        let spanEvent = try XCTUnwrap(core.waitAndReturnSpanEvents().first)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumApplicationID], rumEvent.application.id)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumSessionID], rumEvent.session.id)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumViewID], rumEvent.view.id)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumActionID], rumEvent.action.id)
    }

    func testGivenBundleWithRumEnabled_whenSendingSpanAfterViewIsStopped_itContainsSessionId() throws {
        config.bundleWithRumEnabled = true
        Trace.enable(with: config, in: core)

        // Given
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)
        RUMMonitor.shared(in: core).startView(key: "view", name: "view")

        // When
        RUMMonitor.shared(in: core).stopView(key: "view")
        let span = Tracer.shared(in: core).startSpan(operationName: "operation")
        span.finish()

        // Then
        let rumEvent = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMViewEvent.self).last)
        let spanEvent = try XCTUnwrap(core.waitAndReturnSpanEvents().first)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumApplicationID], rumEvent.application.id)
        XCTAssertEqual(spanEvent.tags[SpanTags.rumSessionID], rumEvent.session.id)
        XCTAssertNil(spanEvent.tags[SpanTags.rumViewID])
        XCTAssertNil(spanEvent.tags[SpanTags.rumActionID])
    }

    func testGivenBundleWithRumDisabled_whenSendingSpan_itDoesNotContainRUMContext() throws {
        config.bundleWithRumEnabled = false
        Trace.enable(with: config, in: core)

        // Given
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)
        RUMMonitor.shared(in: core).startView(key: "view", name: "view")

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "operation")
        span.finish()

        // Then
        let spanEvent = try XCTUnwrap(core.waitAndReturnSpanEvents().first)
        XCTAssertNil(spanEvent.tags[SpanTags.rumApplicationID])
        XCTAssertNil(spanEvent.tags[SpanTags.rumSessionID])
        XCTAssertNil(spanEvent.tags[SpanTags.rumViewID])
        XCTAssertNil(spanEvent.tags[SpanTags.rumActionID])
    }

    // MARK: - Injecting span context into carrier

    func testInjectingAndExtractingSpanContextUsingDatadogCarrier() {
        // Given
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
        let injectedContext = tracer.startSpan(operationName: .mockAny()).context

        // When
        let writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        tracer.inject(spanContext: injectedContext, writer: writer)

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        let extractedContext = tracer.extract(reader: reader)!

        // Then
        XCTAssertEqual(injectedContext.dd.traceID, extractedContext.dd.traceID)
        XCTAssertEqual(injectedContext.dd.spanID, extractedContext.dd.spanID)
        XCTAssertEqual(injectedContext.dd.parentSpanID, extractedContext.dd.parentSpanID)
        XCTAssertEqual(injectedContext.dd.sampleRate, extractedContext.dd.sampleRate)
        XCTAssertEqual(injectedContext.dd.isKept, extractedContext.dd.isKept)
    }

    func testInjectingAndExtractingSpanContextUsingB3SingleCarrier() {
        // Given
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
        let injectedContext = tracer.startSpan(operationName: .mockAny()).context

        // When
        let writer = B3HTTPHeadersWriter(samplingStrategy: .headBased, injectEncoding: .single, traceContextInjection: .all)
        tracer.inject(spanContext: injectedContext, writer: writer)

        let reader = B3HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        let extractedContext = tracer.extract(reader: reader)!

        // Then
        XCTAssertEqual(injectedContext.dd.traceID, extractedContext.dd.traceID)
        XCTAssertEqual(injectedContext.dd.spanID, extractedContext.dd.spanID)
        XCTAssertEqual(injectedContext.dd.parentSpanID, extractedContext.dd.parentSpanID)
        XCTAssertEqual(injectedContext.dd.sampleRate, extractedContext.dd.sampleRate)
        XCTAssertEqual(injectedContext.dd.isKept, extractedContext.dd.isKept)
    }

    func testInjectingAndExtractingSpanContextUsingB3MultipleCarrier() {
        // Given
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
        let injectedContext = tracer.startSpan(operationName: .mockAny()).context

        // When
        let writer = B3HTTPHeadersWriter(samplingStrategy: .headBased, injectEncoding: .multiple, traceContextInjection: .all)
        tracer.inject(spanContext: injectedContext, writer: writer)

        let reader = B3HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        let extractedContext = tracer.extract(reader: reader)!

        // Then
        XCTAssertEqual(injectedContext.dd.traceID, extractedContext.dd.traceID)
        XCTAssertEqual(injectedContext.dd.spanID, extractedContext.dd.spanID)
        XCTAssertEqual(injectedContext.dd.parentSpanID, extractedContext.dd.parentSpanID)
        XCTAssertEqual(injectedContext.dd.sampleRate, extractedContext.dd.sampleRate)
        XCTAssertEqual(injectedContext.dd.isKept, extractedContext.dd.isKept)
    }

    func testInjectingAndExtractingSpanContextUsingW3CCarrier() {
        // Given
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)
        let injectedContext = tracer.startSpan(operationName: .mockAny()).context

        // When
        let writer = W3CHTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        tracer.inject(spanContext: injectedContext, writer: writer)

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        let extractedContext = tracer.extract(reader: reader)!

        // Then
        XCTAssertEqual(injectedContext.dd.traceID, extractedContext.dd.traceID)
        XCTAssertEqual(injectedContext.dd.spanID, extractedContext.dd.spanID)
        XCTAssertEqual(injectedContext.dd.parentSpanID, extractedContext.dd.parentSpanID)
        XCTAssertEqual(injectedContext.dd.sampleRate, extractedContext.dd.sampleRate)
        XCTAssertEqual(injectedContext.dd.isKept, extractedContext.dd.isKept)
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
        config.dateProvider = RelativeDateProvider(using: deviceTime)
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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
        Trace.enable(with: config, in: core)
        let tracer = Tracer.shared(in: core)

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

    func testGivenSDKNotInitialized_whenObtainingSharedTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // given
        let core = NOPDatadogCore()
        Trace.enable(in: core)

        // when
        let tracer = Tracer.shared(in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized and RUM feature must be enabled before calling `Tracer.shared(in:)`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenTraceNotEnabled_whenObtainingSharedTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // given
        let core = FeatureRegistrationCoreMock()
        XCTAssertNil(core.get(feature: TraceFeature.self))

        // when
        let tracer = Tracer.shared(in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Trace feature must be enabled before calling `Tracer.shared(in:)`."
        )
        XCTAssertTrue(tracer is DDNoopTracer)
    }

    func testGivenLoggingFeatureNotEnabled_whenSendingLogFromSpan_itPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // given
        XCTAssertNil(core.get(feature: LogsFeature.self))
        Trace.enable(in: core)

        // when
        let tracer = Tracer.shared(in: core)
        let span = tracer.startSpan(operationName: "foo")
        span.log(fields: ["bar": "bizz"])

        // then
        core.flush()
        XCTAssertEqual(dd.logger.warnLog?.message, "The log for span \"foo\" will not be send, because the Logs feature is not enabled.")
    }
}
// swiftlint:enable multiline_arguments_brackets
