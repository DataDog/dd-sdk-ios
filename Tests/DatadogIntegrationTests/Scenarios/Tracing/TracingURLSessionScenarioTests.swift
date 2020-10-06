/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class TracingURLSessionScenarioTests: IntegrationTests, TracingCommonAsserts {
    func testTracingURLSessionScenario() throws {
        try runTest(for: TracingURLSessionScenario.self)
    }

    func testTracingNSURLSessionScenario() throws {
        try runTest(for: TracingNSURLSessionScenario.self)
    }

    /// Both, `URLSession` (Swift) and `NSURLSession` (Objective-C) scenarios fetch exactly the same
    /// resources, so we can run the same test and assertions.
    private func runTest(for scenario: TestScenario.Type) throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Server session recording custom data requests send to `HTTPServerMock`.
        // Used to assert if trace propagation headers are send to the server.
        let customServerSession = server.obtainUniqueRecordingSession()
        // Server session recording spans send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()

        // URL used for requesting custom GET resource in tested application.
        let customGETResourceURL = URL(
            string: customServerSession.recordingURL.deletingLastPathComponent().absoluteString + "inspect"
        )!
        // URL used for requesting custom POST resource in tested application.
        let customPOSTResourceURL = customServerSession.recordingURL
        // URL used for requesting custom resource which leads to "Bad URL" error.
        let customBadResourceURL = URL(string: "https://foo.bar")!

        let app = ExampleApplication()
        app.launchWith(
            testScenario: scenario,
            serverConfiguration: HTTPServerMockConfiguration(
                tracesEndpoint: tracingServerSession.recordingURL,
                instrumentedEndpoints: [
                    customGETResourceURL,
                    customPOSTResourceURL,
                    customBadResourceURL
                ]
            )
        )

        // Return desired count or timeout
        let recordedTracingRequests = try tracingServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Assert spans
        let spanMatchers = try recordedTracingRequests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        XCTAssertEqual(spanMatchers.count, 3)

        // Assert common things
        assertHTTPHeadersAndPath(in: recordedTracingRequests)
        try assertCommonMetadata(in: spanMatchers)
        try assertThat(spans: spanMatchers, startAfter: testBeginTimeInNanoseconds, andFinishBefore: testEndTimeInNanoseconds)

        let taskWithURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == customGETResourceURL.absoluteString }
        )
        let taskWithRequest = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == customPOSTResourceURL.absoluteString }
        )
        let taskWithBadURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == customBadResourceURL.absoluteString }
        )

        XCTAssertEqual(try taskWithURL.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithRequest.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithBadURL.operationName(), "urlsession.request")

        XCTAssertEqual(try taskWithURL.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithRequest.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithBadURL.metrics.isRootSpan(), 1)

        XCTAssertEqual(try taskWithURL.isError(), 0)
        XCTAssertEqual(try taskWithRequest.isError(), 0)
        XCTAssertEqual(try taskWithBadURL.isError(), 1)

        let customEndpointURL = customServerSession.recordingURL
        XCTAssert(try taskWithURL.resource().contains(customEndpointURL.host!))
        XCTAssertEqual(try taskWithRequest.resource(), customEndpointURL.absoluteString)

        // Assert tracing HTTP headers propagation to custom endpoint
        let recordedCustomRequests = try customServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)
        XCTAssertEqual(recordedCustomRequests.count, 1)

        let recordedCustomRequest = recordedCustomRequests[0]
        let traceID = try taskWithRequest.traceID().hexadecimalNumberToDecimal
        XCTAssert(
            recordedCustomRequest.httpHeaders.contains("x-datadog-trace-id: \(traceID)"),
            "Trace: \(traceID) Actual: \(recordedCustomRequest.httpHeaders)"
        )
        let spanID = try taskWithRequest.spanID().hexadecimalNumberToDecimal
        XCTAssert(
            recordedCustomRequest.httpHeaders.contains("x-datadog-parent-id: \(spanID)"),
            "Span: \(spanID) Actual: \(recordedCustomRequest.httpHeaders)"
        )
        XCTAssert(recordedCustomRequest.httpHeaders.contains("creation-method: dataTaskWithRequest"))
    }
}
