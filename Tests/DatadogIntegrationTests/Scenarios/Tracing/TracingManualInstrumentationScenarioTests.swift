/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class TracingManualInstrumentationScenarioTests: IntegrationTests, TracingCommonAsserts {
    func testTracingManualInstrumentationScenario() throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Server session recording spans send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()
        // Server session recording logs send to `HTTPServerMock`.
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenario: TracingManualInstrumentationScenario.self,
            logsEndpointURL: loggingServerSession.recordingURL,
            tracesEndpointURL: tracingServerSession.recordingURL
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

        XCTAssertEqual(try spanMatchers[0].operationName(), "data downloading")
        XCTAssertEqual(try spanMatchers[1].operationName(), "data presentation")
        XCTAssertEqual(try spanMatchers[2].operationName(), "view loading")

        // All spans share the same `trace_id`
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[1].traceID())
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[2].traceID())

        // "data downloading" and "data presentation" are childs of "view loading"
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), try spanMatchers[2].spanID())
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), try spanMatchers[2].spanID())

        XCTAssertNil(try? spanMatchers[0].metrics.isRootSpan())
        XCTAssertNil(try? spanMatchers[1].metrics.isRootSpan())
        XCTAssertEqual(try spanMatchers[2].metrics.isRootSpan(), 1)

        // "data downloading" span's tags
        XCTAssertEqual(try spanMatchers[0].meta.custom(keyPath: "meta.data.kind"), "image")
        XCTAssertEqual(try spanMatchers[0].meta.custom(keyPath: "meta.data.url"), "https://example.com/image.png")

        // "data presentation" span contains error
        XCTAssertEqual(try spanMatchers[0].isError(), 0)
        XCTAssertEqual(try spanMatchers[1].isError(), 1)
        XCTAssertEqual(try spanMatchers[2].isError(), 0)

        // "data downloading" span has custom resource name
        XCTAssertEqual(try spanMatchers[0].resource(), "GET /image.png")
        XCTAssertEqual(try spanMatchers[1].resource(), try spanMatchers[1].operationName())
        XCTAssertEqual(try spanMatchers[2].resource(), try spanMatchers[2].operationName())

        // assert baggage item:
        XCTAssertEqual(try spanMatchers[0].meta.custom(keyPath: "meta.class"), "SendTracesFixtureViewController")
        XCTAssertEqual(try spanMatchers[1].meta.custom(keyPath: "meta.class"), "SendTracesFixtureViewController")
        XCTAssertEqual(try spanMatchers[2].meta.custom(keyPath: "meta.class"), "SendTracesFixtureViewController")

        // Assert logs requests
        let recordedLoggingRequests = try loggingServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        // Assert logs
        let logMatchers = try recordedLoggingRequests
            .flatMap { request in try LogMatcher.fromArrayOfJSONObjectsData(request.httpBody) }

        XCTAssertEqual(logMatchers.count, 1)

        logMatchers[0].assertStatus(equals: "info")
        logMatchers[0].assertMessage(equals: "download progress")
        logMatchers[0].assertValue(forKey: "progress", equals: 0.99)

        // Assert logs are linked to "data downloading" span
        logMatchers[0].assertValue(forKey: "dd.trace_id", equals: try spanMatchers[0].traceID().hexadecimalNumberToDecimal)
        logMatchers[0].assertValue(forKey: "dd.span_id", equals: try spanMatchers[0].spanID().hexadecimalNumberToDecimal)
    }
}
