/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogTrace

private class InstrumentedSessionDelegate: NSObject, URLSessionDataDelegate {}

class RUMResourceTraceIntegrationTests: RUMSessionTestsBase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testNoActiveSpan_traceSampled_sessionSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: true)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: true)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: true)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: true)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: false)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: false)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: false)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: false, sampled: false)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: true)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: true)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: true)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: true)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: false)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: false)
        initRUM(sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: false)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = initTraceAndMakeSpan(active: true, sampled: false)
        initRUM(sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    private func initTraceAndMakeSpan(active: Bool, sampled: Bool) -> OTSpan {
        Trace.enable(
            with: Trace.Configuration(sampleRate: sampled ? 90 : 5),
            in: core
        )

        let span = Tracer.shared(in: core).startRootSpan(operationName: "test-op")
        if active {
            span.setActive()
        }
        return span
    }

    private func initRUM(sessionSampled: Bool, urlSessionTrackingSampled: Bool) {
        var config = RUM.Configuration(
            applicationID: .mockAny(),
            sessionSampleRate: sessionSampled ? 80 : 20,
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(
                    hosts: ["example.com"],
                    sampleRate: urlSessionTrackingSampled ? 70 : 10
                )
            )
        )
        // This session ID is not sampled at 50%, but it is sampled at 60%.
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!))
        RUM.enable(with: config, in: core)
    }

    enum SamplingExpectation {
        case activeSpan
        case rum
        case sessionNotSampled
        case sessionSampledRequestNotSampled
    }

    private func performRequestAndVerifyIfSampled(_ expectation: SamplingExpectation, span: OTSpan) throws {
        let request = try sendURLSessionRequest(to: URL.mockAny(), using: InstrumentedSessionDelegate())
        let matchers = try core.waitAndReturnRUMEventMatchers()
        let possibleResourceMatcher = try matchers.first(where: { try $0.eventType() == "resource" })

        if expectation == .sessionNotSampled {
            XCTAssertNil(possibleResourceMatcher)
            return
        }

        let resourceMatcher = try XCTUnwrap(possibleResourceMatcher)

        if expectation == .sessionSampledRequestNotSampled {
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-parent-id"))
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-trace-id"))
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"))
            XCTAssertNil(request.value(forHTTPHeaderField: "traceparent"))
            return
        }

        let spanIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.span_id"))
        let spanID = SpanID(spanIDString, representation: .decimal)
        let traceIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.trace_id"))
        let traceID = TraceID(traceIDString, representation: .hexadecimal)
        let sessionSampleRate: Float = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.configuration.session_sample_rate"))
        let spanDD = try XCTUnwrap(span.context.dd)

        XCTAssertNotEqual(spanID, spanDD.spanID)
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-datadog-parent-id"), spanDD.spanID.toString(representation: .decimal))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"), "1")

        if expectation == .rum {
            XCTAssertNotEqual(traceID, span.context.dd?.traceID)
            XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-datadog-trace-id"), spanDD.traceID.toString(representation: .decimal))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
            XCTAssertEqual(sessionSampleRate, 70)
        } else { // expectation == .activeSpan
            let parentSpanIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.parent_span_id"))
            let parentSpanID = SpanID(parentSpanIDString, representation: .decimal)
            XCTAssertEqual(traceID, spanDD.traceID)
            XCTAssertEqual(parentSpanID, spanDD.spanID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-trace-id"), spanDD.traceID.toString(representation: .decimal))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
            XCTAssertEqual(sessionSampleRate, 90)
        }

        print(matchers)
    }

    private func sendURLSessionRequest(to url: URL, using delegate: URLSessionDelegate, completionHandler: (() -> Void)? = nil) throws -> URLRequest {
        let server = ServerMock(delivery: .success(response: .mockAny(), data: .mockAny()))
        let session = server.getInterceptedURLSession(delegate: delegate)
        let taskCompleted = expectation(description: "wait for task completion")
        let task = session.dataTask(with: .mockWith(url: url)) { _, _, _ in
            completionHandler?()
            taskCompleted.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 5)

        let requests = server.waitAndReturnRequests(count: 1)
        return try XCTUnwrap(requests.first)
    }
}
