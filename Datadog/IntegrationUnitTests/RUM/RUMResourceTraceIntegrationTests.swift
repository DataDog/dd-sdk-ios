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
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    private func prepare(activeSpan: Bool, spanSampled: Bool, sessionSampled: Bool, urlSessionTrackingSampled: Bool) -> OTSpan {
        Trace.enable(
            with: Trace.Configuration(sampleRate: spanSampled ? 90 : 5),
            in: core
        )

        var config = RUM.Configuration(
            applicationID: .mockAny(),
            sessionSampleRate: sessionSampled ? 80 : 20,
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(
                    hosts: ["www.example.com"],
                    sampleRate: urlSessionTrackingSampled ? 70 : 10
                )
            )
        )
        // This session ID is not sampled at 50%, but it is sampled at 60%.
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!))
        RUM.enable(with: config, in: core)

        // We need to wait for all the messages between features to stabilize so we have everything setup correctly.
        core.flush()

        let span = Tracer.shared(in: core).startRootSpan(operationName: "test-op")
        if activeSpan {
            span.setActive()
        }
        return span
    }

    enum SamplingExpectation {
        case activeSpan
        case rum
        case sessionNotSampled
        case sessionSampledRequestNotSampled
    }

    private func performRequestAndVerifyIfSampled(_ expectation: SamplingExpectation, span: OTSpan) throws {
        let request = try sendURLSessionRequest(to: URL.mockAny())
        // Finish the span to leave the os_activity scope. Without this, repeated setActive()
        // calls across tests accumulate nested os_activity scopes that can corrupt the activity
        // hierarchy and cause getActiveSpan() to return nil in subsequent tests.
        span.finish()

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
            XCTAssertEqual(sessionSampleRate, 80)
        } else { // expectation == .activeSpan
            let parentSpanIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.parent_span_id"))
            let parentSpanID = SpanID(parentSpanIDString, representation: .decimal)
            XCTAssertEqual(traceID, spanDD.traceID)
            XCTAssertEqual(parentSpanID, spanDD.spanID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-trace-id"), spanDD.traceID.toString(representation: .decimal))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
            XCTAssertEqual(sessionSampleRate, 80)
        }
    }
}
