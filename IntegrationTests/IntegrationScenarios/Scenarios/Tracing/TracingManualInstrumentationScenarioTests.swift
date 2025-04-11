/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

class TracingManualInstrumentationScenarioTests: IntegrationTests, TracingCommonAsserts, LoggingCommonAsserts {
    func testTracingManualInstrumentationScenario() throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Server session recording spans send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()
        // Server session recording logs send to `HTTPServerMock`.
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "TracingManualInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL,
                tracesEndpoint: tracingServerSession.recordingURL
            )
        )

        // Get expected number of `SpanMatchers`
        let recordedTracingRequests = try tracingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try SpanMatcher.from(requests: requests).count == 3
        }
        let spanMatchers = try SpanMatcher.from(requests: recordedTracingRequests)

        assertTracing(requests: recordedTracingRequests)

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        try assertCommonMetadata(in: spanMatchers)
        try assertThat(spans: spanMatchers, startAfter: testBeginTimeInNanoseconds, andFinishBefore: testEndTimeInNanoseconds)

        XCTAssertEqual(try spanMatchers[0].operationName(), "data downloading")
        XCTAssertEqual(try spanMatchers[1].operationName(), "data presentation")
        XCTAssertEqual(try spanMatchers[2].operationName(), "view loading")

        // All spans share the same `trace_id`
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[1].traceID())
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[2].traceID())

        // "data downloading" and "data presentation" are children of "view loading"
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
        let recordedLoggingRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count == 2
        }

        assertLogging(requests: recordedLoggingRequests)

        let logMatchers = try LogMatcher.from(requests: recordedLoggingRequests)

        logMatchers[0].assertStatus(equals: "info")
        logMatchers[0].assertMessage(equals: "download progress")
        logMatchers[0].assertValue(forKey: "progress", equals: 0.99)
        logMatchers[1].assertStatus(equals: "error")
        let matcher = { (str: String) in str.contains("SendTracesFixtureViewController") }
        logMatchers[1].assertValue(forKeyPath: "message", matches: matcher)
        logMatchers[1].assertValue(forKeyPath: "error.kind", matches: matcher)
        logMatchers[1].assertValue(forKeyPath: "error.message", matches: matcher)
        logMatchers[1].assertValue(forKeyPath: "error.stack", matches: matcher)

        // Assert logs are linked to "data downloading" span
        logMatchers[0].assertValue(forKey: "dd.trace_id", equals: try spanMatchers[0].traceID()?.toString(representation: .hexadecimal))
        logMatchers[0].assertValue(forKey: "dd.span_id", equals: try spanMatchers[0].spanID()?.toString(representation: .hexadecimal))
        logMatchers[1].assertValue(forKey: "dd.trace_id", equals: try spanMatchers[1].traceID()?.toString(representation: .hexadecimal))
        logMatchers[1].assertValue(forKey: "dd.span_id", equals: try spanMatchers[1].spanID()?.toString(representation: .hexadecimal))
    }
}
