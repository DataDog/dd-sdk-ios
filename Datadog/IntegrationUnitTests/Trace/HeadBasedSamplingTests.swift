/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogTrace
import DatadogInternal
import TestUtilities

private class InstrumentedSessionDelegate: NSObject, URLSessionDataDelegate {}

class HeadBasedSamplingTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var traceConfig: Trace.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        traceConfig = Trace.Configuration()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        traceConfig = nil
        super.tearDown()
    }

    // MARK: - Local Tracing

    // TODO: RUM-3470 Enable this test when head-based sampling is supported
    func testSamplingLocalTrace() throws {
        let localTraceSampling: Float = 50

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent")
        let child = Tracer.shared(in: core).startSpan(operationName: "child", childOf: parent.context)
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: parent.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 3, "It must send all spans")

        let allKept = spans.filter({ $0.isKept }).count == 3
        let allDropped = spans.filter({ !$0.isKept }).count == 3
        XCTAssertTrue(allKept || allDropped, "All spans must be either kept or dropped")
    }

    // TODO: RUM-3470 Enable this test when head-based sampling is supported
    func testSamplingLocalTraceWithImplicitParent() throws {
        let localTraceSampling: Float = 50

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent").setActive()
        let child1 = Tracer.shared(in: core).startSpan(operationName: "child 1")
        let child2 = Tracer.shared(in: core).startSpan(operationName: "child 2")
        child1.finish()
        child2.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 3, "It must send all spans")

        let allKept = spans.filter({ $0.isKept }).count == 3
        let allDropped = spans.filter({ !$0.isKept }).count == 3
        XCTAssertTrue(allKept || allDropped, "All spans must be either kept or dropped")
    }

    // MARK: - Distributed Tracing

    // TODO: RUM-3470 Enable this test when head-based sampling is supported
    func testSendingSampledDistributedTraceWithNoParent() throws {
        /*
         This is the situation where distributed trace starts with the span created with DatadogTrace network
         instrumentation (with no parent):

         dd-sdk-ios:         [--- urlsession.request ---]   keep
         client backend:        [--- backend span ---]      keep
         */

        let localTraceSampling: Float = 0 // drop all
        let distributedTraceSampling: Float = 100 // keep all

        // Given
        traceConfig.sampleRate = localTraceSampling
        traceConfig.urlSessionTracking = .init(
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())

        // Then
        let span = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.samplingRate, 1, "Span must use distributed trace sample rate")
        XCTAssertTrue(span.isKept, "Span must be sampled")

        // Then
        let expectedTraceIDField = String(span.traceID.idLo)
        let expectedSpanIDField = String(span.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(span.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
    }

    // TODO: RUM-3535 Enable this test when trace context injection control is implemented
    func testSendingDroppedDistributedTraceWithNoParent() throws {
        /*
         This is the situation where distributed trace starts with the span created with DatadogTrace network
         instrumentation (with no parent):

         dd-sdk-ios:         [--- urlsession.request ---]   drop
         client backend:        [--- backend span ---]      drop
         */

        let localTraceSampling: Float = 100 // keep all
        let distributedTraceSampling: Float = 0 // drop all

        // Given
        traceConfig.sampleRate = localTraceSampling
        traceConfig.urlSessionTracking = .init(
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())

        // Then
        let span = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.samplingRate, 0, "Span must use distributed trace sample rate")
        XCTAssertFalse(span.isKept, "Span must be dropped")

        // Then
        let expectedTraceIDField = span.traceID.idLoHex
        let expectedSpanIDField = String(span.spanID, representation: .hexadecimal)
        let expectedTagsField = "_dd.p.tid=\(span.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    // TODO: RUM-3470 Enable this test when head-based sampling is supported
    func testSendingSampledDistributedTraceWithParent() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with DatadogTrace network instrumentation:

         client-ios-app:     [-------- active.span -----------]   keep
         dd-sdk-ios:            [--- urlsession.request ---]      keep
         client backend:           [--- backend span ---]         keep
         */

        let localTraceSampling: Float = 100 // keep all
        let distributedTraceSampling: Float = 0 // drop all

        // Given
        traceConfig.sampleRate = localTraceSampling
        traceConfig.urlSessionTracking = .init(
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())
        span.finish()

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        let activeSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "active.span" }))
        let urlsessionSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "urlsession.request" }))

        XCTAssertEqual(activeSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(activeSpan.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(urlsessionSpan.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(urlsessionSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = String(activeSpan.traceID.idLo)
        let expectedSpanIDField = String(urlsessionSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
    }

    // TODO: RUM-3535 Enable this test when trace context injection control is implemented
    func testSendingDroppedDistributedTraceWithParent() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with DatadogTrace network instrumentation:

         client-ios-app:     [-------- active.span -----------]   drop
         dd-sdk-ios:            [--- urlsession.request ---]      drop
         client backend:           [--- backend span ---]         drop
         */

        let localTraceSampling: Float = 0 // drop all
        let distributedTraceSampling: Float = 100 // keep all

        // Given
        traceConfig.sampleRate = localTraceSampling
        traceConfig.urlSessionTracking = .init(
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())
        span.finish()

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        let activeSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "active.span" }))
        let urlsessionSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "urlsession.request" }))

        XCTAssertEqual(activeSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(activeSpan.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(urlsessionSpan.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(urlsessionSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = activeSpan.traceID.idLoHex
        let expectedSpanIDField = String(urlsessionSpan.spanID, representation: .hexadecimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
    }

    // MARK: - Helpers

    /// Sends request to `url` using real `URLSession` instrumented with provided `delegate`.
    /// It returns the actual request that was sent to the server which can include additional headers set by the SDK.
    private func sendURLSessionRequest(to url: String, using delegate: URLSessionDelegate) throws -> URLRequest {
        let server = ServerMock(delivery: .success(response: .mockAny(), data: .mockAny()))
        let session = server.getInterceptedURLSession(delegate: delegate)
        let taskCompleted = expectation(description: "wait for task completion")
        let task = session.dataTask(with: .mockWith(url: URL(string: url)!)) { _, _, _ in taskCompleted.fulfill() }
        task.resume()
        waitForExpectations(timeout: 5)

        let requests = server.waitAndReturnRequests(count: 1)
        return try XCTUnwrap(requests.first)
    }
}
