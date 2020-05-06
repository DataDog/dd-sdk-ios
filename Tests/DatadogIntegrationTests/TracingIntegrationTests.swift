/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class TracingIntegrationTests: IntegrationTests {
    private struct Constants {
        /// Time needed for traces to be uploaded to mock server.
        static let tracesDeliveryTime: TimeInterval = 30
    }

    func testLaunchTheAppAndSendTraces() throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        let app = ExampleApplication()
        app.launchWith(mockServerURL: serverSession.recordingURL)
        app.tapSendTracesForUITests()

        // Wait for delivery
        Thread.sleep(forTimeInterval: Constants.tracesDeliveryTime)

        // Assert requests
        let recordedRequests = try serverSession.getRecordedPOSTRequests()
        recordedRequests.forEach { request in
            XCTAssertTrue(request.path.contains("/ui-tests-client-token?ddsource=mobile"))
            XCTAssertTrue(request.httpHeaders.contains("Content-Type: text/plain;charset=UTF-8"))
        }

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Assert spans
        let spanMatchers = try recordedRequests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        XCTAssertEqual(try spanMatchers[0].operationName(), "data downloading")
        XCTAssertEqual(try spanMatchers[1].operationName(), "data presentation")
        XCTAssertEqual(try spanMatchers[2].operationName(), "view appearing")

        // they share the same `trace_id`
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[1].traceID())
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[2].traceID())

        // "downloading" and "presentation" are childs of "view appearing"
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), try spanMatchers[2].spanID())
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), try spanMatchers[2].spanID())

        XCTAssertNil(try? spanMatchers[0].metrics.isRootSpan())
        XCTAssertNil(try? spanMatchers[1].metrics.isRootSpan())
        XCTAssertEqual(try spanMatchers[2].metrics.isRootSpan(), 1)

        try spanMatchers.forEach { matcher in
            XCTAssertGreaterThan(try matcher.startTime(), testBeginTimeInNanoseconds)
            XCTAssertLessThan(try matcher.startTime(), testEndTimeInNanoseconds)

            XCTAssertEqual(try matcher.serviceName(), "ui-tests-service-name")
            XCTAssertEqual(try matcher.resource(), try matcher.operationName())
            XCTAssertEqual(try matcher.type(), "custom")
            XCTAssertEqual(try matcher.isError(), 0)
            XCTAssertEqual(try matcher.environment(), "staging")

            XCTAssertEqual(try matcher.meta.source(), "mobile")
            XCTAssertEqual(try matcher.meta.tracerVersion().split(separator: ".").count, 3)
            XCTAssertEqual(try matcher.meta.applicationVersion(), "1.0")

            XCTAssertTrue(
                SpanMatcher.allowedNetworkReachabilityValues.contains(
                    try matcher.meta.networkReachability()
                )
            )

            try matcher.meta.networkAvailableInterfaces().split(separator: "+").forEach { interface in
                XCTAssertTrue(
                    SpanMatcher.allowedNetworkAvailableInterfacesValues.contains(String(interface))
                )
            }

            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv4()))
            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv6()))
            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsExpensive()))
            if #available(iOS 13.0, *) {
                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsConstrained()))
            }

            #if targetEnvironment(simulator)
                // When running on iOS Simulator
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierName())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP())
            #else
                // When running on physical device with SIM card registered
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierName())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP())
            #endif
        }
    }
}
