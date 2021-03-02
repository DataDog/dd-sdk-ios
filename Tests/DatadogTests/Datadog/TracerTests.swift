/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class TracerTests: XCTestCase {
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

    // MARK: - Customizing Tracer

    func testSendingSpanWithDefaultTracer() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationVersion: "1.0.0",
                    applicationBundleIdentifier: "com.datadoghq.ios-sdk",
                    serviceName: "default-service-name",
                    environment: "custom"
                )
            ),
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            ),
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1)
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation")
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
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
        """)
    }

    func testSendingSpanWithCustomizedTracer() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                sendNetworkInfo: true
            )
        )

        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
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
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(
            configuration: .init(
                serviceName: "custom-service-name",
                globalTags: [
                    "globaltag1": "globalValue1",
                    "globaltag2": "globalValue2"
                ]
            )
        )

        let span = tracer.startSpan(operationName: .mockAny())
        span.setTag(key: "globaltag2", value: "overwrittenValue" )
        span.finish()

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(try spanMatcher.serviceName(), "custom-service-name")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag1"), "globalValue1")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.globaltag2"), "overwrittenValue")
    }

    // MARK: - Sending Customized Spans

    func testSendingCustomizedSpan() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

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

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.resource(), "GET /foo.png")
        XCTAssertEqual(try spanMatcher.startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatcher.duration(), 500_000_000)
        XCTAssertEqual(try spanMatcher.isError(), 1)
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag1"), "string value")
        XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag2"), "123")
    }

    func testSendingSpanWithParentAndBaggageItems() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 3)
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

    func testSendingSpanWithActiveSpanAsAParent() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 3)
        let rootMatcher = spanMatchers[2]
        let child1Matcher = spanMatchers[1]
        let child2Matcher = spanMatchers[0]

        XCTAssertEqual(try rootMatcher.parentSpanID(), "0")
        XCTAssertEqual(try child1Matcher.parentSpanID(), try rootMatcher.spanID())
        XCTAssertEqual(try child2Matcher.parentSpanID(), try rootMatcher.spanID())
    }

    func testSendingSpansWithNoParent() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd
        let queue = DispatchQueue(label: "\(#function)-queue")

        func makeAPIRequest(completion: @escaping () -> Void) {
            queue.asyncAfter(deadline: .now() + 1) {
                completion()
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 2)
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), "0")
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), "0")
    }

    func testStartingRootActiveSpanInAsynchronousJobs() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())
        let queue = DispatchQueue(label: "\(#function)")

        func makeFakeAPIRequest(on queue: DispatchQueue, completion: @escaping () -> Void) {
            let requestSpan = tracer.startRootSpan(operationName: "request").setActive()
            queue.asyncAfter(deadline: .now() + 1) {
                let responseDecodingSpan = tracer.startSpan(operationName: "response decoding")
                responseDecodingSpan.finish()
                requestSpan.finish()
                completion()
            }
        }
        makeFakeAPIRequest(on: queue) {}
        makeFakeAPIRequest(on: queue) {}

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 4)
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
        Datadog.instance = Datadog(
            consentProvider: ConsentProvider(initialConsent: .granted),
            userInfoProvider: UserInfoProvider(),
            launchTimeProvider: LaunchTimeProviderMock()
        )
        defer { Datadog.instance = nil }

        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                userInfoProvider: Datadog.instance!.userInfoProvider
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: "span with no user info").finish()

        Datadog.setUserInfo(id: "abc-123", name: "Foo")
        tracer.startSpan(operationName: "span with user `id` and `name`").finish()

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
        tracer.startSpan(operationName: "span with user `id`, `name`, `email` and `extraInfo`").finish()

        Datadog.setUserInfo(id: nil, name: nil, email: nil)
        tracer.startSpan(operationName: "span with no user info").finish()

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 4)
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
        let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: nil)
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                carrierInfoProvider: carrierInfoProvider
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 2)
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
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                networkConnectionInfoProvider: networkConnectionInfoProvider
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 2)
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

    // MARK: - Sending spans with different network and battery conditions

    func testGivenBadBatteryConditions_itDoesNotTryToSendTraces() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                mobileDevice: .mockWith(
                    currentBatteryStatus: { () -> MobileDevice.BatteryStatus in
                        .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                    }
                )
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: .mockAny()).finish()

        server.waitAndAssertNoRequestsSent()
    }

    func testGivenNoNetworkConnection_itDoesNotTryToSendTraces() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                    networkConnectionInfo: .mockWith(reachability: .no)
                )
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: .mockAny()).finish()

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Sending tags

    func testSendingSpanTagsOfDifferentEncodableValues() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init()).dd

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

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
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
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
            )
        )
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp)
            ),
            loggingFeature: LoggingFeature.instance!
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.log(fields: [OTLogFields.event: "error", OTLogFields.errorKind: "Swift error", OTLogFields.message: "Ops!"])

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)

        let regularLogMatcher = logMatchers[0]
        let errorLogMatcher = logMatchers[1]

        regularLogMatcher.assertStatus(equals: "info")
        regularLogMatcher.assertMessage(equals: "hello")
        regularLogMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        regularLogMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
        regularLogMatcher.assertValue(forKey: "custom.field", equals: "value")

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
    }

    func testSendingSpanLogsWithErrorFromArguments() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
            )
        )
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp)
            ),
            loggingFeature: LoggingFeature.instance!
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.setError(kind: "Swift error", message: "Ops!")

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)
        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
    }

    func testSendingSpanLogsWithErrorFromNSError() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
            )
        )
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp)
            ),
            loggingFeature: LoggingFeature.instance!
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        let error = NSError(
            domain: "Tracer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Ops!"]
        )
        span.setError(error)

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)

        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Tracer - 1")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
    }

    func testSendingSpanLogsWithErrorFromSwiftError() throws {
        LoggingFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
            )
        )
        defer { LoggingFeature.instance = nil }

        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp)
            ),
            loggingFeature: LoggingFeature.instance!
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: "operation", startTime: .mockDecember15th2019At10AMUTC())
        span.log(fields: [OTLogFields.message: "hello", "custom.field": "value"])
        span.setError(ErrorMock("Ops!"))

        let logMatchers = try LoggingFeature.waitAndReturnLogMatchers(count: 2)

        let errorLogMatcher = logMatchers[1]

        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "ErrorMock")
        errorLogMatcher.assertMessage(equals: "Ops!")
        errorLogMatcher.assertValue(forKey: "dd.trace_id", equals: "\(span.context.dd.traceID.rawValue)")
        errorLogMatcher.assertValue(forKey: "dd.span_id", equals: "\(span.context.dd.spanID.rawValue)")
    }

    // MARK: - Integration With RUM Feature

    func testGivenBundlingWithRUMEnabledAndRUMMonitorRegistered_whenSendingSpan_itContainsCurrentRUMContext() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        // given
        let tracer = Tracer.initialize(configuration: .init()).dd
        Global.rum = RUMMonitor.initialize()
        Global.rum.startView(viewController: mockView)
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        let span = tracer.startSpan(operationName: "operation", tags: [:], startTime: Date())
        span.finish()

        // then
        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(
            try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.applicationID)"),
            try XCTUnwrap(RUMFeature.instance?.configuration.applicationID)
        )
        XCTAssertValidRumUUID(try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.sessionID)"))
        XCTAssertValidRumUUID(try spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.viewID)"))
    }

    func testGivenBundlingWithRUMEnabledButRUMMonitorNotRegistered_whenSendingSpan_itPrintsWarning() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // given
        let tracer = Tracer.initialize(configuration: .init()).dd
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // when
        let span = tracer.startSpan(operationName: "operation", tags: [:], startTime: Date())
        span.finish()

        // then
        XCTAssertEqual(output.recordedLog?.status, .warn)
        try XCTAssertTrue(
            XCTUnwrap(output.recordedLog?.message)
                .contains("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Tracing will not work.")
        )

        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertNil(try? spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.applicationID)"))
        XCTAssertNil(try? spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.sessionID)"))
        XCTAssertNil(try? spanMatcher.meta.custom(keyPath: "meta.\(RUMContextIntegration.Attributes.viewID)"))
    }

    // MARK: - Injecting span context into carrier

    func testItInjectsSpanContextWithHTTPHeadersWriter() {
        let tracer: Tracer = .mockAny()
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = HTTPHeadersWriter()
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        let expectedHTTPHeaders = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testItExtractsSpanContextWithHTTPHeadersReader() {
        let tracer: Tracer = .mockAny()
        let injectedSpanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny(), baggageItems: .mockAny())

        let httpHeadersWriter = HTTPHeadersWriter()
        tracer.inject(spanContext: injectedSpanContext, writer: httpHeadersWriter)

        let httpHeadersReader = HTTPHeadersReader(
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
        let serverTimeDifference = TimeInterval.random(in: -5..<5).rounded() // few seconds difference

        // When
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(using: deviceTime),
                dateCorrector: DateCorrectorMock(correctionOffset: serverTimeDifference)
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        let span = tracer.startSpan(operationName: .mockAny())
        span.finish(at: deviceTime.addingTimeInterval(2)) // 2 seconds long span

        // Then
        let spanMatcher = try TracingFeature.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(
            try spanMatcher.startTime(),
            deviceTime.addingTimeInterval(serverTimeDifference).timeIntervalSince1970.toNanoseconds,
            "The `startTime` should be using server time."
        )
        XCTAssertEqual(
            try spanMatcher.duration(),
            2_000_000_000,
            "The `duration` should remain unaffected."
        )
    }

    // MARK: - Tracking Consent

    func testWhenChangingConsentValues_itUploadsOnlyAuthorizedSpans() throws {
        let consentProvider = ConsentProvider(initialConsent: .pending)

        // Given
        TracingFeature.instance = .mockByRecordingSpanMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(consentProvider: consentProvider)
        )
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())

        // When
        tracer.startSpan(operationName: "span in `.pending` consent changed to `.granted`").finish()
        consentProvider.changeConsent(to: .granted)
        tracer.startSpan(operationName: "span in `.granted` consent").finish()
        consentProvider.changeConsent(to: .notGranted)
        tracer.startSpan(operationName: "span in `.notGranted` consent").finish()
        consentProvider.changeConsent(to: .granted)
        tracer.startSpan(operationName: "another span in `.granted` consent").finish()

        // Then
        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 3)
        XCTAssertEqual(try spanMatchers[0].operationName(), "span in `.pending` consent changed to `.granted`")
        XCTAssertEqual(try spanMatchers[1].operationName(), "span in `.granted` consent")
        XCTAssertEqual(try spanMatchers[2].operationName(), "another span in `.granted` consent")
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }

        let tracer = Tracer.initialize(configuration: .init())
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
    }

    func testWhenSpanStateChangesFromDifferentThreads_itChangesSpanState() {
        TracingFeature.instance = .mockNoOp()
        defer { TracingFeature.instance = nil }
        let tracer = Tracer.initialize(configuration: .init())
        let span = tracer.startSpan(operationName: "some span", childOf: nil).dd

        let closures: [(DDSpan) -> Void] = [
            // swiftlint:disable opening_brace
            { span in span.setTag(key: .mockRandom(), value: "value") },
            { span in span.setBaggageItem(key: .mockRandom(), value: "value") },
            { span in _ = span.baggageItem(withKey: .mockRandom()) },
            { span in _ = span.context.forEachBaggageItem { _, _ in return false } },
            { span in span.log(fields: [.mockRandom(): "value"]) }
            // swiftlint:enable opening_brace
        ]
        /// Calls given closures on each span cuncurrently
        let iterations = 100
        DispatchQueue.concurrentPerform(iterations: iterations) { iteration in
            closures.forEach { $0(span) }
        }
        XCTAssertEqual(span.tags.count, iterations)
        XCTAssertEqual(span.logFields.count, iterations)
    }

    // MARK: - Usage errors

    func testGivenDatadogNotInitialized_whenInitializingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(Datadog.instance)

        // when
        let tracer = Tracer.initialize(configuration: .init())

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Tracer.initialize()`."
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

        try Datadog.deinitializeOrThrow()
    }

    func testGivenLoggingFeatureDisabled_whenSendingLogFromSpan_itPrintsWarning() throws {
        // given
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableLogging(false)
                .build()
        )

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // when
        let tracer = Tracer.initialize(configuration: .init())
        let span = tracer.startSpan(operationName: "foo")
        span.log(fields: ["bar": "bizz"])

        // then
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(output.recordedLog?.message, "The log for span \"foo\" will not be send, because the Logging feature is disabled.")

        try Datadog.deinitializeOrThrow()
    }

    func testGivenTracerInitialized_whenInitializingAnotherTime_itPrintsError() throws {
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

        try Datadog.deinitializeOrThrow()
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

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // Given
        let tracingHandler = try XCTUnwrap(URLSessionAutoInstrumentation.instance?.interceptor.handler)

        // When
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // Then
        tracingHandler.notify_taskInterceptionCompleted(interception: TaskInterception(request: .mockAny(), isFirstParty: true))
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            `URLSession` request was completed, but no `Tracer` is registered on `Global.sharedTracer`. Tracing auto instrumentation will not work.
            Make sure `Global.sharedTracer = Tracer.initialize()` is called before any network request is send.
            """
        )

        URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Environment Context

    func testSendingSpansWithNoDirectParentAndEnvironmentContext() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        setenv("x-datadog-trace-id", "111111", 1)
        setenv("x-datadog-parent-id", "222222", 1)

        let tracer = Tracer.initialize(configuration: .init()).dd
        let queue = DispatchQueue(label: "\(#function)-queue")

        func makeAPIRequest(completion: @escaping () -> Void) {
            queue.asyncAfter(deadline: .now() + 1) {
                completion()
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 2)
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), TracingUUID(rawValue: 222_222).toHexadecimalString)
        XCTAssertEqual(try spanMatchers[0].traceID(), TracingUUID(rawValue: 111_111).toHexadecimalString)
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), TracingUUID(rawValue: 222_222).toHexadecimalString)
        XCTAssertEqual(try spanMatchers[1].traceID(), TracingUUID(rawValue: 111_111).toHexadecimalString)

        unsetenv("x-datadog-trace-id")
        unsetenv("x-datadog-parent-id")
    }

    func testSendingSpanWithActiveSpanAsAParentAndEnvironmentContext() throws {
        TracingFeature.instance = .mockByRecordingSpanMatchers(directories: temporaryFeatureDirectories)
        defer { TracingFeature.instance = nil }

        setenv("x-datadog-trace-id", "111111", 1)
        setenv("x-datadog-parent-id", "222222", 1)

        let tracer = Tracer.initialize(configuration: .init()).dd
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

        let spanMatchers = try TracingFeature.waitAndReturnSpanMatchers(count: 3)
        let rootMatcher = spanMatchers[2]
        let child1Matcher = spanMatchers[1]
        let child2Matcher = spanMatchers[0]

        XCTAssertEqual(try rootMatcher.parentSpanID(), TracingUUID(rawValue: 222_222).toHexadecimalString)
        XCTAssertEqual(try spanMatchers[0].traceID(), TracingUUID(rawValue: 111_111).toHexadecimalString)
        XCTAssertEqual(try child1Matcher.parentSpanID(), try rootMatcher.spanID())
        XCTAssertEqual(try child1Matcher.traceID(), TracingUUID(rawValue: 111_111).toHexadecimalString)
        XCTAssertEqual(try child2Matcher.parentSpanID(), try rootMatcher.spanID())
        XCTAssertEqual(try child2Matcher.traceID(), TracingUUID(rawValue: 111_111).toHexadecimalString)

        unsetenv("x-datadog-trace-id")
        unsetenv("x-datadog-parent-id")
    }
}
// swiftlint:enable multiline_arguments_brackets
