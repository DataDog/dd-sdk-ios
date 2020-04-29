/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import OpenTracing
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
// swiftlint:disable trailing_closure
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

    // MARK: - Sending spans

    func testSendingMinimalSpan() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            appContext: .mockWith(
                bundleIdentifier: "com.datadoghq.ios-sdk",
                bundleVersion: "1.0.0",
                bundleShortVersion: "1.0.0"
            ),
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1)
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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
              "service": "ios",
              "resource": "operation",
              "start": 1576404000000000000,
              "duration": 500000000,
              "error": 0,
              "type": "custom",
              "meta.tracer.version": "\(sdkVersion)",
              "meta.application.version": "1.0.0",
              "meta._dd.source": "mobile",
              "meta.network.client.available_interfaces": "wifi",
              "meta.network.client.is_constrained": "0",
              "meta.network.client.is_expensive": "1",
              "meta.network.client.reachability": "yes",
              "meta.network.client.sim_carrier.allows_voip": "0",
              "meta.network.client.sim_carrier.iso_country": "abc",
              "meta.network.client.sim_carrier.name": "abc",
              "meta.network.client.sim_carrier.technology": "LTE",
              "meta.network.client.supports_ipv4": "1",
              "meta.network.client.supports_ipv6": "1",
              "metrics._top_level": 1,
              "metrics._sampling_priority_v1": 1
            }
          ],
          "env": "staging"
        }
        """) // TOOD: RUMM-422 Network info is not send by default with spans
    }

    func testSendingCustomizedSpan() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

        let span = tracer.startSpan(operationName: "operation", tags: ["tag1": "value1"], startTime: .mockDecember15th2019At10AMUTC())
        span.finish(at: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        let spanMatcher = try server.waitAndReturnSpanMatchers(count: 1)[0]
        XCTAssertEqual(try spanMatcher.operationName(), "operation")
        XCTAssertEqual(try spanMatcher.startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatcher.duration(), 500_000_000)
        // TODO: RUMM-402 assert custom `meta.*`
        // TODO: RUMM-403 assert custom `metrics.*`
    }

    func testSendingSpanWithParent() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

        let rootSpan = tracer.startSpan(operationName: "root operation")
        let childSpan = tracer.startSpan(operationName: "child operation", childOf: rootSpan.context)
        let grandchildSpan = tracer.startSpan(operationName: "grandchild operation", childOf: childSpan.context)
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

        XCTAssertEqual(try childMatcher.operationName(), "child operation")
        XCTAssertEqual(try childMatcher.traceID(), rootSpan.context.dd.traceID.toHexadecimalString)
        XCTAssertEqual(try childMatcher.parentSpanID(), rootSpan.context.dd.spanID.toHexadecimalString)
        XCTAssertNil(try? childMatcher.metrics.isRootSpan())

        XCTAssertEqual(try rootMatcher.operationName(), "root operation")
        XCTAssertEqual(try rootMatcher.parentSpanID(), "0")
        XCTAssertEqual(try rootMatcher.metrics.isRootSpan(), 1)

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

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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
            appContext: .mockWith(
                mobileDevice: .mockWith(
                    currentBatteryStatus: { () -> MobileDevice.BatteryStatus in
                        .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                    }
                )
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

        tracer.startSpan(operationName: .mockAny()).finish()

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Injecting span context into carrier

    func testItInjectsSpanContextIntoHTTPHeadersWriter() {
        let tracer = DDTracer(spanOutput: SpanOutputMock())
        let spanContext = DDSpanContext(traceID: 1, spanID: 2, parentSpanID: .mockAny())

        let httpHeadersWriter = DDHTTPHeadersWriter()
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, [:])

        tracer.inject(spanContext: spanContext, writer: httpHeadersWriter)

        let expectedHTTPHeaders = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
        ]
        XCTAssertEqual(httpHeadersWriter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    // MARK: - Initialization

    // TODO: RUMM-339 Move this test to obj-c wrapper tests, similarly to what we do for `DDLoggerBuilderTests`
    func testGivenDatadogNotInitialized_whenUsingTracer_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        XCTAssertNil(Datadog.instance)

        let tracer = DDTracer(spanOutput: SpanOutputMock())
        let fixtures: [(() -> Void, String)] = [
            ({ _ = tracer.startSpan(operationName: .mockAny()) },
             "`Datadog.initialize()` must be called prior to `startSpan(...)`."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleError in
            tracerMethod()
            XCTAssertEqual(printFunction.printedMessage, "🔥 Datadog SDK usage error: \(expectedConsoleError)")
        }
    }
}
// swiftlint:enable multiline_arguments_brackets
// swiftlint:enable trailing_closure
