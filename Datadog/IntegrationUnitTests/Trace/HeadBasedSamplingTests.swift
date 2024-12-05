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

    func testSamplingLocalTrace() throws {
        /*
         This is the basic situation of local trace with 3 spans:

         client-ios-app:     [-------- parent -----------]   |
         client-ios-app:        [----- child --------]       | all 3: keep or drop
         client-ios-app:           [-- grandchild --]        |
         */
        let localTraceSampling: SampleRate = 50 // keep or drop

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

    func testSamplingLocalTraceWithImplicitParent() throws {
        /*
         This is the situation of local trace with active span as a parent:

         client-ios-app:     [-------- active.span -----]   |
         client-ios-app:       [- child1 -][- child2 -]     | all 3: keep or drop
         */
        let localTraceSampling: SampleRate = 50 // keep or drop

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent").setActive()
        let child1 = Tracer.shared(in: core).startSpan(operationName: "child 1")
        child1.finish()
        let child2 = Tracer.shared(in: core).startSpan(operationName: "child 2")
        child2.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 3, "It must send all spans")

        let allKept = spans.filter({ $0.isKept }).count == 3
        let allDropped = spans.filter({ !$0.isKept }).count == 3
        XCTAssertTrue(allKept || allDropped, "All spans must be either kept or dropped")
    }

    // MARK: - Distributed Tracing (through network instrumentation API)

    func testSendingSampledDistributedTraceWithNoParent_throughURLSessionInstrumentationAPI() throws {
        /*
         This is the situation where distributed trace starts with the span created with DatadogTrace network
         instrumentation (with no parent):

         dd-sdk-ios:         [--- urlsession.request ---]   keep
         client backend:        [--- backend span ---]      keep
         */

        let localTraceSampling: SampleRate = 0 // drop all
        let distributedTraceSampling: SampleRate = .maxSampleRate // keep all

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

    func testSendingDroppedDistributedTraceWithNoParent_throughURLSessionInstrumentationAPI() throws {
        /*
         This is the situation where distributed trace starts with the span created with DatadogTrace network
         instrumentation (with no parent):

         dd-sdk-ios:         [--- urlsession.request ---]   drop
         client backend:        [--- backend span ---]      drop
         */

        let localTraceSampling: SampleRate = .maxSampleRate // keep all
        let distributedTraceSampling: SampleRate = 0 // drop all

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
        let expectedTraceIDField = span.traceID.toString(representation: .decimal)
        let expectedSpanIDField = span.spanID.toString(representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(span.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    func testSendingSampledDistributedTraceWithParent_throughURLSessionInstrumentationAPI() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with DatadogTrace network instrumentation:

         client-ios-app:     [-------- active.span -----------]   keep
         dd-sdk-ios:            [--- urlsession.request ---]      keep
         client backend:           [--- backend span ---]         keep
         */

        let localTraceSampling: SampleRate = .maxSampleRate // keep all
        let distributedTraceSampling: SampleRate = 0 // drop all

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

    func testSendingDroppedDistributedTraceWithParent_throughURLSessionInstrumentationAPI() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with DatadogTrace network instrumentation:

         client-ios-app:     [-------- active.span -----------]   drop
         dd-sdk-ios:            [--- urlsession.request ---]      drop
         client backend:           [--- backend span ---]         drop
         */

        let localTraceSampling: SampleRate = 0 // drop all
        let distributedTraceSampling: SampleRate = .maxSampleRate // keep all

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

        XCTAssertEqual(activeSpan.samplingRate, 0, "Span must use local trace sample rate")
        XCTAssertFalse(activeSpan.isKept, "Span must not be sampled")
        XCTAssertEqual(urlsessionSpan.samplingRate, 0, "Span must use local trace sample rate")
        XCTAssertFalse(urlsessionSpan.isKept, "Span must not be sampled")
        XCTAssertEqual(urlsessionSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(urlsessionSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = activeSpan.traceID.toString(representation: .decimal)
        let expectedSpanIDField = urlsessionSpan.spanID.toString(representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    // MARK: - Distributed Tracing (through Tracer API)

    func testSendingSampledDistributedTraceWithNoParent_throughTracerAPI() throws {
        /*
         This is the situation where distributed trace starts with the span created with Datadog tracer:

         client-ios-app:     [------ network.span ------]   keep
         client backend:        [--- backend span ---]      keep
         */

        let localTraceSampling: SampleRate = .maxSampleRate // keep all

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        var request: URLRequest = .mockAny()
        let writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()

        // Then
        let networkSpan = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(networkSpan.operationName, "network.span")
        XCTAssertEqual(networkSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(networkSpan.isKept, "Span must be sampled")

        // Then
        let expectedTraceIDField = String(networkSpan.traceID.idLo)
        let expectedSpanIDField = String(networkSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(networkSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
    }

    func testSendingDroppedDistributedTraceWithNoParent_throughTracerAPI() throws {
        /*
         This is the situation where distributed trace starts with the span created with Datadog tracer:

         client-ios-app:     [------ network.span ------]   drop
         client backend:        [--- backend span ---]      drop
         */

        let localTraceSampling: SampleRate = 0 // drop all

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        var request: URLRequest = .mockAny()
        let writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()

        // Then
        let networkSpan = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(networkSpan.operationName, "network.span")
        XCTAssertEqual(networkSpan.samplingRate, 0, "Span must use local trace sample rate")
        XCTAssertFalse(networkSpan.isKept, "Span must be dropped")

        // Then
        let expectedTraceIDField = networkSpan.traceID.toString(representation: .decimal)
        let expectedSpanIDField = networkSpan.spanID.toString(representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(networkSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    func testSendingSampledDistributedTraceWithParent_throughTracerAPI() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with Datadog tracer:

         client-ios-app:     [-------- active.span -----------]   keep
         client-ios-app:         [------ network.span ------]     keep
         client backend:            [--- backend span ---]        keep
         */

        let localTraceSampling: SampleRate = .maxSampleRate // keep all

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        var request: URLRequest = .mockAny()
        let writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        let parentSpan = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()
        parentSpan.finish()

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        let activeSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "active.span" }))
        let networkSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "network.span" }))

        XCTAssertEqual(activeSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(activeSpan.isKept, "Span must be sampled")
        XCTAssertEqual(networkSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(networkSpan.isKept, "Span must be sampled")
        XCTAssertEqual(networkSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(networkSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = String(activeSpan.traceID.idLo)
        let expectedSpanIDField = String(networkSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
    }

    func testSendingDroppedDistributedTraceWithParent_throughTracerAPI() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with Datadog tracer:

         client-ios-app:     [-------- active.span -----------]   drop
         client-ios-app:         [------ network.span ------]     drop
         client backend:            [--- backend span ---]        drop
         */

        let localTraceSampling: SampleRate = 0 // drop all

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        var request: URLRequest = .mockAny()
        let writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all)
        let parentSpan = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()
        parentSpan.finish()

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        let activeSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "active.span" }))
        let networkSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "network.span" }))

        XCTAssertEqual(activeSpan.samplingRate, 0, "Span must use local trace sample rate")
        XCTAssertFalse(activeSpan.isKept, "Span must be dropped")
        XCTAssertEqual(networkSpan.samplingRate, 0, "Span must use local trace sample rate")
        XCTAssertFalse(networkSpan.isKept, "Span must be dropped")
        XCTAssertEqual(networkSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(networkSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = activeSpan.traceID.toString(representation: .decimal)
        let expectedSpanIDField = networkSpan.spanID.toString(representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex)"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
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
