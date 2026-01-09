/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogTrace
@_spi(Internal)
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

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
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
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: child.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()

        guard spans.isEmpty else {
            XCTAssertEqual(spans.filter({ $0.samplingPriority.isKept }).count, 3, "All spans must be either kept or dropped")
            return
        }
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

        guard spans.isEmpty else {
            XCTAssertEqual(spans.filter({ $0.samplingPriority.isKept }).count, 3, "All spans must be either kept or dropped")
            return
        }
    }

    func testManuallyKeepLocalTrace() throws {
        /*
         Situation where the local trace is marked as manual keep on the root span before any
         child is created:

         client-ios-app:     [-------- parent -----------]   |
         client-ios-app:        [----- child --------]       | all 3: manual keep
         client-ios-app:           [-- grandchild --]        |
         */
        let localTraceSampling: SampleRate = 0 // Drop

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent")
        parent.setTag(key: SpanTags.manualKeep, value: true)
        let child = Tracer.shared(in: core).startSpan(operationName: "child", childOf: parent.context)
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: child.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()

        XCTAssertEqual(spans.count, 3)
        spans.forEach { span in
            XCTAssertEqual(span.samplingPriority, .manualKeep)
            XCTAssertEqual(span.samplingDecisionMaker, .manual)
        }
    }

    func testManuallyDropLocalTrace() throws {
        /*
         Situation where the local trace is marked as manual drop on the root span before any
         child is created:

         client-ios-app:     [-------- parent -----------]   |
         client-ios-app:        [----- child --------]       | all 3: manual drop
         client-ios-app:           [-- grandchild --]        |
         */
        let localTraceSampling: SampleRate = 100 // Keep

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent")
        parent.setTag(key: SpanTags.manualDrop, value: true)
        let child = Tracer.shared(in: core).startSpan(operationName: "child", childOf: parent.context)
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: child.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()

        XCTAssertEqual(spans.count, 0)
    }

    func testManuallyDropChildLocalTrace() throws {
        /*
         Situation where the local trace is marked as manual drop on a child span:

         client-ios-app:     [-------- parent -----------]   |
         client-ios-app:        [----- child --------]       | all 3: manual drop
         client-ios-app:           [-- grandchild --]        |
         */
        let localTraceSampling: SampleRate = 100 // Keep

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent")
        let child = Tracer.shared(in: core).startSpan(operationName: "child", childOf: parent.context)
        child.setTag(key: SpanTags.manualDrop, value: true)
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: child.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 0)
    }

    func testManuallyKeepChildLocalTrace() throws {
        /*
         Situation where the local trace is marked as manual keep on a child span:

         client-ios-app:     [-------- parent -----------]   |
         client-ios-app:        [----- child --------]       | all 3: manual keep
         client-ios-app:           [-- grandchild --]        |
         */
        let localTraceSampling: SampleRate = 0 // Drop

        // Given
        traceConfig.sampleRate = localTraceSampling
        Trace.enable(with: traceConfig, in: core)

        // When
        let parent = Tracer.shared(in: core).startSpan(operationName: "parent")
        let child = Tracer.shared(in: core).startSpan(operationName: "child", childOf: parent.context)
        child.setTag(key: SpanTags.manualKeep, value: true)
        let grandchild = Tracer.shared(in: core).startSpan(operationName: "grandchild", childOf: child.context)
        grandchild.finish()
        child.finish()
        parent.finish()

        let spans = core.waitAndReturnSpanEvents()

        XCTAssertEqual(spans.count, 3)
        spans.forEach { span in
            XCTAssertEqual(span.samplingPriority, .manualKeep)
            XCTAssertEqual(span.samplingDecisionMaker, .manual)
        }
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
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())

        // Then
        let span = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.samplingRate, 1, "Span must use distributed trace sample rate")
        XCTAssertTrue(span.samplingPriority.isKept, "Span must be sampled")

        // Then
        let expectedTraceIDField = String(span.traceID.idLo)
        let expectedSpanIDField = String(span.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(span.traceID.idHiHex),_dd.p.dm=-1"
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
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling, traceControlInjection: .all)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate())

        // Then
        XCTAssertNil(core.waitAndReturnSpanEvents().first, "It should not send span event")
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField))
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
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate()) {
            span.finish()
        }

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        let activeSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "active.span" }))
        let urlsessionSpan = try XCTUnwrap(spanEvents.first(where: { $0.operationName == "urlsession.request" }))

        XCTAssertEqual(activeSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(activeSpan.samplingPriority.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(urlsessionSpan.samplingPriority.isKept, "Span must be sampled")
        XCTAssertEqual(urlsessionSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(urlsessionSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = String(activeSpan.traceID.idLo)
        let expectedSpanIDField = String(urlsessionSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex),_dd.p.dm=-1"
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
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling, traceControlInjection: .all)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate()) {
            span.finish()
        }

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        XCTAssertNil(spanEvents.first(where: { $0.operationName == "active.span" }))
        XCTAssertNil(spanEvents.first(where: { $0.operationName == "urlsession.request" }))

        // Then
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField))
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    func testSendingDroppedDistributedTraceWithParent_throughURLSessionInstrumentationAPI_noInjection() throws {
        /*
         This is the situation where distributed trace starts with an active local span and is continued with the span
         created with DatadogTrace network instrumentation:

         client-ios-app:     [-------- active.span -----------]   manual drop
         dd-sdk-ios:            [--- urlsession.request ---]      manual drop
         client backend:           [--- backend span ---]         server decision
         */

        let localTraceSampling: SampleRate = .maxSampleRate // keep all
        let distributedTraceSampling: SampleRate = .maxSampleRate // keep all

        // Given
        traceConfig.sampleRate = localTraceSampling
        traceConfig.urlSessionTracking = .init(
            firstPartyHostsTracing: .trace(hosts: ["foo.com"], sampleRate: distributedTraceSampling, traceControlInjection: .sampled)
        )
        Trace.enable(with: traceConfig, in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedSessionDelegate.self), in: core)

        // When
        let span = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        span.setTag(key: SpanTags.manualDrop, value: true)
        let request = try sendURLSessionRequest(to: "https://foo.com/request", using: InstrumentedSessionDelegate()) {
            span.finish()
        }

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spanEvents.count, 0)

        // Then
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField))
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
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()

        // Then
        let networkSpan = try XCTUnwrap(core.waitAndReturnSpanEvents().first, "It should send span event")
        XCTAssertEqual(networkSpan.operationName, "network.span")
        XCTAssertEqual(networkSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(networkSpan.samplingPriority.isKept, "Span must be sampled")

        // Then
        let expectedTraceIDField = String(networkSpan.traceID.idLo)
        let expectedSpanIDField = String(networkSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(networkSpan.traceID.idHiHex),_dd.p.dm=-1"
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), expectedTraceIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), expectedSpanIDField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), expectedTagsField)
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
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
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()

        // Then
        XCTAssertNil(core.waitAndReturnSpanEvents().first, "It should not send span event")

        // Then
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField))
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
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
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
        XCTAssertTrue(activeSpan.samplingPriority.isKept, "Span must be sampled")
        XCTAssertEqual(networkSpan.samplingRate, 1, "Span must use local trace sample rate")
        XCTAssertTrue(networkSpan.samplingPriority.isKept, "Span must be sampled")
        XCTAssertEqual(networkSpan.traceID, activeSpan.traceID)
        XCTAssertEqual(networkSpan.parentID, activeSpan.spanID)

        // Then
        let expectedTraceIDField = String(activeSpan.traceID.idLo)
        let expectedSpanIDField = String(networkSpan.spanID, representation: .decimal)
        let expectedTagsField = "_dd.p.tid=\(activeSpan.traceID.idHiHex),_dd.p.dm=-1"
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
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        let parentSpan = Tracer.shared(in: core).startSpan(operationName: "active.span").setActive()
        let span = Tracer.shared(in: core).startSpan(operationName: "network.span")
        Tracer.shared(in: core).inject(spanContext: span.context, writer: writer)
        writer.traceHeaderFields.forEach { field, value in request.setValue(value, forHTTPHeaderField: field) }
        span.finish()
        parentSpan.finish()

        // Then
        let spanEvents = core.waitAndReturnSpanEvents()
        XCTAssertNil(spanEvents.first(where: { $0.operationName == "active.span" }))
        XCTAssertNil(spanEvents.first(where: { $0.operationName == "network.span" }))

        // Then
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNotNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField))
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    // MARK: - Helpers

    /// Sends request to `url` using real `URLSession` instrumented with provided `delegate`.
    /// It returns the actual request that was sent to the server which can include additional headers set by the SDK.
    ///
    /// # Implementation note
    /// `completionHandler` runs as part of `session.dataTask`'s completion handler. This is useful to finish
    /// active (or parent) spans in a more realistic way. Here's a description of problem this solves.
    ///
    /// By the end of a request interception, the `DatadogURLSessionHandler.interceptionDidComplete(interception:)`
    /// method is called. In situations where a span should be created to trace this request, that span is created inside this
    /// method. This span can be a child of a currently active span, or a root span if no active span is present.
    ///
    /// If the SDK users want to trace a process that includes a request, one possibility is setting an active span before
    /// initiating the request, and finishing it when the request ends, using the `DataTask` completion handler. Given
    /// how interception implemented, `interceptionDidComplete(interception:)` runs after that completion
    /// handler, which means if the active span is removed on the completion handler, there would not be an active session
    /// any more.
    ///
    /// The SDK handles this situation (as well as if the SDK users immediately finish the active span after initiating the
    /// request), so this is not a problem. However, in tests, we want to make sure this happens as we expect.
    ///
    /// In this specific method, and unlike most real world code, we block the main thread waiting for test expectations
    /// after initiating the request. In the previous implementation, any active span would be terminated inside the test,
    /// after we returned from this method, meaning after the entire request interception finished. This would not test
    /// if the request interceptors handled correctly the fact the active session is gone by the end of the request, but still
    /// existed in the beginning. Therefore, `completionHandler` was added, and runs as part of the `DataTask`
    /// completion handler. This allows tests to finish active spans inside this completion handler, in a more realistic way,
    /// close to what real world apps would do.
    private func sendURLSessionRequest(to url: String, using delegate: URLSessionDelegate, completionHandler: (() -> Void)? = nil) throws -> URLRequest {
        let server = ServerMock(delivery: .success(response: .mockAny(), data: .mockAny()))
        let session = server.getInterceptedURLSession(delegate: delegate)
        let taskCompleted = expectation(description: "wait for task completion")
        let task = session.dataTask(with: .mockWith(url: URL(string: url)!)) { _, _, _ in
            completionHandler?()
            taskCompleted.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 5)

        let requests = server.waitAndReturnRequests(count: 1)
        return try XCTUnwrap(requests.first)
    }
}
