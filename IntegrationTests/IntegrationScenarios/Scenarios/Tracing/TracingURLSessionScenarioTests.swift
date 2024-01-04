/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapSend3rdPartyRequests() {
        buttons["Send 3rd party requests"].tap()
    }
}

class TracingURLSessionScenarioTests: IntegrationTests, TracingCommonAsserts {
    func testTracingURLSessionScenario_composition() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyComposition,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testTracingURLSessionScenario_legacyWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testTracingURLSessionScenario_directWithGlobalFirstPartyHosts() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingURLSessionScenario_delegateUsingFeatureFirstPartyHosts() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .delegateUsingFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingURLSessionScenario_delegateWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .delegateWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testTracingURLSessionScenario_inheritance() throws {
        try runTest(
            for: "TracingURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyInheritance,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingNSURLSessionScenario_composition() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyComposition,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingNSURLSessionScenario_legacyWithFeatureFirstPartyHosts() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testTracingNSURLSessionScenario_legacyWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingNSURLSessionScenario_delegateUsingFeatureFirstPartyHosts() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .delegateUsingFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testTracingNSURLSessionScenario_delegateWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .delegateWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testTracingNSURLSessionScenario_inheritance() throws {
        try runTest(
            for: "TracingNSURLSessionScenario",
            urlSessionSetup: .init(
                instrumentationMethod: .legacyInheritance,
                initializationMethod: .afterSDK
            )
        )
    }

    /// Both, `URLSession` (Swift) and `NSURLSession` (Objective-C) scenarios fetch exactly the same
    /// resources, so we can run the same test and assertions.
    private func runTest(for testScenarioClassName: String, urlSessionSetup: URLSessionSetup) throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Server session recording first party requests send to `HTTPServerMock`.
        // Used to assert that trace propagation headers are send for first party requests.
        let customFirstPartyServerSession = server.obtainUniqueRecordingSession()

        // Server session recording `Spans` send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()

        // Requesting this first party by the app should create the `SpanEvent`.
        let firstPartyGETResourceURL = URL(
            string: customFirstPartyServerSession.recordingURL.deletingLastPathComponent().absoluteString + "inspect"
        )!
        // Requesting this first party by the app should create the `SpanEvent`.
        let firstPartyPOSTResourceURL = customFirstPartyServerSession.recordingURL
        // Requesting this first party by the app should create the `SpanEvent` with error.
        let firstPartyBadResourceURL = URL(string: "https://foo.bar/")!

        // Requesting this third party by the app should NOT create the `SpanEvent`.
        let thirdPartyGETResourceURL = URL(string: "https://bitrise.io")!
        // Requesting this third party by the app should NOT create the `SpanEvent`.
        let thirdPartyPOSTResourceURL = URL(string: "https://bitrise.io/about")!

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: testScenarioClassName,
            serverConfiguration: HTTPServerMockConfiguration(
                tracesEndpoint: tracingServerSession.recordingURL,
                instrumentedEndpoints: [
                    firstPartyGETResourceURL,
                    firstPartyPOSTResourceURL,
                    firstPartyBadResourceURL,
                    thirdPartyGETResourceURL,
                    thirdPartyPOSTResourceURL
                ]
            ),
            urlSessionSetup: urlSessionSetup
        )
        app.tapSend3rdPartyRequests()

        // Get expected number of `SpanMatchers`
        let recordedTracingRequests = try tracingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try SpanMatcher.from(requests: requests).count >= 3
        }
        let spanMatchers = try SpanMatcher.from(requests: recordedTracingRequests)

        assertTracing(requests: recordedTracingRequests)

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        try assertCommonMetadata(in: spanMatchers)
        try assertThat(spans: spanMatchers, startAfter: testBeginTimeInNanoseconds, andFinishBefore: testEndTimeInNanoseconds)

        let taskWithURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyGETResourceURL.absoluteString },
            "`SpanEvent` should be send for `firstPartyGETResourceURL`"
        )
        let taskWithRequest = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyPOSTResourceURL.absoluteString },
            "`SpanEvent` should be send for `firstPartyPOSTResourceURL`"
        )
        let taskWithBadURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyBadResourceURL.absoluteString },
            "`SpanEvent` should be send for `firstPartyBadResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyGETResourceURL.absoluteString },
            "`SpanEvent` should NOT bet send for `thirdPartyGETResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyPOSTResourceURL.absoluteString },
            "`SpanEvent` should NOT bet send for `thirdPartyPOSTResourceURL`"
        )

        XCTAssertEqual(try taskWithURL.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithRequest.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithBadURL.operationName(), "urlsession.request")

        XCTAssertEqual(try taskWithURL.meta.custom(keyPath: "meta.http.url"), "redacted")
        XCTAssertEqual(try taskWithRequest.meta.custom(keyPath: "meta.http.url"), "redacted")
        XCTAssertEqual(try taskWithBadURL.meta.custom(keyPath: "meta.http.url"), "redacted")

        XCTAssertEqual(try taskWithURL.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithRequest.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithBadURL.metrics.isRootSpan(), 1)

        XCTAssertEqual(try taskWithURL.isError(), 0)
        XCTAssertEqual(try taskWithRequest.isError(), 0)
        XCTAssertEqual(try taskWithBadURL.isError(), 1)

        XCTAssertGreaterThan(try taskWithURL.duration(), 0)
        XCTAssertGreaterThan(try taskWithRequest.duration(), 0)
        XCTAssertGreaterThan(try taskWithBadURL.duration(), 0)

        // Assert tracing HTTP headers propagated to `firstPartyPOSTResourceURL`
        let firstPartyRequests = try customFirstPartyServerSession
            .pullRecordedRequests(timeout: dataDeliveryTimeout) { $0.count >= 1 }

        XCTAssertEqual(firstPartyRequests.count, 1)

        let firstPartyRequest = firstPartyRequests[0]
        XCTAssertEqual(firstPartyRequest.httpHeaders["x-datadog-trace-id"], try taskWithRequest.traceID().hexadecimalNumberToDecimal)
        XCTAssertEqual(firstPartyRequest.httpHeaders["x-datadog-parent-id"], try taskWithRequest.spanID().hexadecimalNumberToDecimal)
        XCTAssertEqual(firstPartyRequest.httpHeaders["x-datadog-sampling-priority"], "1")
        XCTAssertNil(firstPartyRequest.httpHeaders["x-datadog-origin"])
    }
}
