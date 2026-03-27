/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogTrace

class TracingURLSessionHandlerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var core: PassthroughCoreMock!
    var tracer: DatadogTracer!
    var handler: TracingURLSessionHandler!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        let receiver = ContextMessageReceiver()
        core = PassthroughCoreMock(messageReceiver: receiver)

        tracer = .mockWith(
            core: core,
            traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
            spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 1)
        )

        handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a,_dd.p.dm=-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "000000000000000a0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000064")
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000064-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000064-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.tracestate), "dd=p:0000000000000064;s:1;t.dm:-1")
        XCTAssertNil(capturedState)

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.samplingPriority.isKept)
    }

    func testGivenFirstPartyInterception_withSampledTrace_itDoesNotOverwriteTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        // When
        var orgRequest: URLRequest = .mockWith(url: "https://www.example.com")
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.tagsField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Single.b3Field)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.traceparent)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.tracestate)

        let (request, traceContext, capturedState) = handler.modify(
            request: orgRequest,
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.tracestate), "custom")
        XCTAssertNil(capturedState)

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: 0,
            firstPartyHosts: .init(),
            traceContextInjection: .sampled,
            telemetry: NOPTelemetry()
        )

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field))
        XCTAssertNil(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent))
        XCTAssertNil(capturedState)

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withActiveSpan_itInjectParentSpanID() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        span.finish()

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a,_dd.p.dm=-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "101")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "000000000000000a0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000065")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000065-1-0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000065-01")
        assert(capturedState: capturedState, has: span)

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 101)
        XCTAssertEqual(injectedTraceContext.parentSpanID, span.context.dd.spanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, span.context.dd.sampleRate)
        XCTAssertEqual(injectedTraceContext.samplingPriority.isKept, span.context.dd.samplingDecision.samplingPriority.isKept)
    }

    func testGivenFirstPartyInterception_withActiveManuallyKeptSpan_itInjectExpectedHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()
        span.setTag(key: SpanTags.manualKeep, value: true)

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        span.finish()

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a,_dd.p.dm=-4")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "101")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "2")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "000000000000000a0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000065")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000065-1-0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000065-01")
        assert(capturedState: capturedState, has: span)

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 101)
        XCTAssertEqual(injectedTraceContext.parentSpanID, span.context.dd.spanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, span.context.dd.sampleRate)
        XCTAssertEqual(injectedTraceContext.samplingPriority.isKept, span.context.dd.samplingDecision.samplingPriority.isKept)
    }

    func testGivenFirstPartyInterception_withActiveManuallyDroppedSpanAndInjectingAll_itInjectExpectedHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()
        span.setTag(key: SpanTags.manualDrop, value: true)

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        span.finish()

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "101")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "000000000000000a0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000065")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000065-0-0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000065-00")
        assert(capturedState: capturedState, has: span)

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 101)
        XCTAssertEqual(injectedTraceContext.parentSpanID, span.context.dd.spanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, span.context.dd.sampleRate)
        XCTAssertEqual(injectedTraceContext.samplingPriority.isKept, span.context.dd.samplingDecision.samplingPriority.isKept)
    }

    func testGivenFirstPartyInterception_withActiveManuallyDroppedSpanAndInjectingSampled_itDoesNotInjectTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: 0,
            firstPartyHosts: .init(),
            traceContextInjection: .sampled,
            telemetry: NOPTelemetry()
        )

        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()
        span.setTag(key: SpanTags.manualDrop, value: true)

        // When
        let (request, traceContext, capturedState) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789",
                    sessionSampler: .mockKeepAll()
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field))
        XCTAssertNil(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent))
        assert(capturedState: capturedState, has: span)

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterceptionWithSpanContext_whenInterceptionCompletes_itUsesInjectedSpanContext() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }
        let sampleRate: Float = .mockRandom(min: 1, max: 100)
        let samplingDecision = SamplingDecision.autoKept()

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true,
            trackingMode: .registeredDelegate
        )
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )
        interception.register(trace: TraceContext(
            traceID: 100,
            spanID: 200,
            parentSpanID: nil,
            sampleRate: sampleRate,
            samplingPriority: samplingDecision.samplingPriority,
            samplingDecisionMaker: samplingDecision.decisionMaker,
            rumSessionId: nil
        ))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)

        XCTAssertEqual(String(span.traceID, representation: .decimal), "100")
        XCTAssertEqual(String(span.spanID, representation: .decimal), "200")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.duration, 1)
        XCTAssertEqual(span.samplingRate, sampleRate / 100)
        XCTAssertEqual(span.samplingPriority, samplingDecision.samplingPriority)
        XCTAssertEqual(span.samplingDecisionMaker, samplingDecision.decisionMaker)
    }

    func testGivenFirstPartyInterceptionWithNoError_whenInterceptionCompletes_itEncodesRequestInfoInSpan() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let request: ImmutableRequest = .mockWith(httpMethod: "POST")
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.duration, 2)
        XCTAssertEqual(span.resource, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "POST")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "200")
        XCTAssertEqual(span.tags[OTTags.spanKind], "client")
        XCTAssertEqual(span.tags.count, 6)
    }

    func testGivenFirstPartyIncompleteInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let incompleteInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true, trackingMode: .registeredDelegate)
        // With duration breakdown, interception is incomplete without both metrics and completion

        // When
        handler.interceptionDidComplete(interception: incompleteInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenThirdPartyInterception_withRegisteredDelegate_itDoesNotSendTheSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given - with duration breakdown
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: false, trackingMode: .registeredDelegate)
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenThirdPartyInterception_inAutomaticMode_itDoesNotSendTheSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given - automatic mode
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: false, trackingMode: .automatic)
        interception.register(response: .mockAny(), error: nil)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testRUM2APMInterception_withRegisteredDelegate_itDoesNotSendTheSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given - with duration breakdown
        let request: ImmutableRequest = .mockWith(
            allHTTPHeaderFields: [TracingHTTPHeaders.originField: "rum"]
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: false, trackingMode: .registeredDelegate)
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testRUM2APMInterception_inAutomaticMode_itDoesNotSendTheSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given - automatic mode
        let request: ImmutableRequest = .mockWith(
            allHTTPHeaderFields: [TracingHTTPHeaders.originField: "rum"]
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: false, trackingMode: .automatic)
        interception.register(response: .mockAny(), error: nil)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenAnyInterception_itAddsAppStateInformationToSpan() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 10)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.tags[SpanTags.foregroundDuration], "10000000000")
        XCTAssertEqual(span.tags[SpanTags.isBackground], "false")
    }

    func testGivenRejectingHandler_itDoesNotRecordSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let receiver = ContextMessageReceiver()

        let handler = TracingURLSessionHandler(
            tracer: .mockWith(core: core),
            contextReceiver: receiver,
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        core.context.applicationStateHistory = .mockAppInForeground()

        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 10)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5)
    }

    // MARK: - Automatic Mode Support

    func testGivenAutomaticModeInterception_withApproximateTiming_itCreatesSpan() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockWith(httpMethod: "GET"),
            isFirstParty: true,
            trackingMode: .automatic // Using automatic mode (no URLSessionTaskMetrics)
        )
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        // Register approximate timing (simulating what NetworkInstrumentationFeature does)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 3))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.duration, 3, accuracy: 0.1, "Span duration should be approximately 3 seconds")
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "200")
    }

    func testGivenAutomaticModeInterception_withSpanContext_itUsesInjectedSpanContext() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }
        let sampleRate: Float = .mockRandom(min: 1, max: 100)
        let samplingDecision = SamplingDecision.autoKept()

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true,
            trackingMode: .automatic
        )
        interception.register(response: .mockAny(), error: nil)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))
        interception.register(trace: TraceContext(
            traceID: 300,
            spanID: 400,
            parentSpanID: nil,
            sampleRate: sampleRate,
            samplingPriority: samplingDecision.samplingPriority,
            samplingDecisionMaker: samplingDecision.decisionMaker,
            rumSessionId: nil
        ))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(String(span.traceID, representation: .decimal), "300")
        XCTAssertEqual(String(span.spanID, representation: .decimal), "400")
        XCTAssertEqual(span.samplingRate, sampleRate / 100)
    }

    func testGivenAutomaticModeInterception_withoutTiming_itDoesNotCreateSpan() throws {
        let expectation = expectation(description: "Do not send span")
        expectation.isInverted = true
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true,
            trackingMode: .automatic
        )
        interception.register(response: .mockAny(), error: nil)
        // Note: No startDate or endDate registered

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenRegisteredDelegate_whenBothTimingsAvailable_itPrefersMetricsTiming() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let metricsStart = Date.mockDecember15th2019At10AMUTC()
        let metricsEnd = metricsStart.addingTimeInterval(2.5) // 2.5s duration (accurate)
        let approxStart = metricsStart.addingTimeInterval(0.1) // 100ms later
        let approxEnd = metricsEnd.addingTimeInterval(0.15) // 150ms later

        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true,
            trackingMode: .registeredDelegate
        )
        interception.register(response: .mockAny(), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(start: metricsStart, end: metricsEnd)
            )
        )
        // Also register approximate timing (simulating dual capture)
        interception.register(startDate: approxStart)
        interception.register(endDate: approxEnd)

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        // Should use metrics timing (2.5s), not approximate timing (~2.55s)
        XCTAssertEqual(span.duration, 2.5, accuracy: 0.01, "Should use accurate metrics timing")
    }

    func testGivenAutomaticModeInterception_withError_itEncodesErrorInSpan() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let mockError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        let interception = URLSessionTaskInterception(
            request: .mockWith(httpMethod: "POST"),
            isFirstParty: true,
            trackingMode: .automatic
        )
        interception.register(response: nil, error: mockError)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "POST")
    }

    func testGivenAutomaticModeInterception_with4xxError_itEncodesClientErrorInSpan() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true,
            trackingMode: .automatic
        )
        interception.register(response: .mockResponseWith(statusCode: 404), error: nil)
        interception.register(startDate: .mockDecember15th2019At10AMUTC())
        interception.register(endDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.2))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "404")
        XCTAssertEqual(span.resource, "404", "404 responses should have resource set to '404'")
    }

    // MARK: - Span Customization Tests

    func testGivenSpanCustomization_whenInterceptionCompletes_itCallsCustomizationWithAllParameters() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        var receivedRequest: Trace.Configuration.InterceptedRequest?
        var receivedSpan: OTSpan?
        var receivedResponse: URLResponse?
        var receivedError: Error?

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: { request, span, response, error in
                receivedRequest = request
                receivedSpan = span
                receivedResponse = response
                receivedError = error
                span.setTag(key: "graphql.operation.name", value: "GetUser")
            }
        )

        // Given
        let requestBody = #"{"operationName":"GetUser"}"#.data(using: .utf8)
        let request: ImmutableRequest = .mockWith(
            url: URL(string: "https://www.example.com/graphql")!,
            httpMethod: "POST",
            httpBody: requestBody
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNotNil(receivedRequest, "Customization callback should receive the request")
        XCTAssertEqual(receivedRequest?.url?.absoluteString, "https://www.example.com/graphql")
        XCTAssertEqual(receivedRequest?.httpMethod, "POST")
        XCTAssertEqual(receivedRequest?.httpBody, requestBody, "Customization callback should receive the request body")
        XCTAssertNotNil(receivedSpan, "Customization callback should receive the span")
        XCTAssertNotNil(receivedResponse, "Customization callback should receive the response")
        XCTAssertEqual((receivedResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(receivedError, "Error should be nil for successful requests")

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        // Custom tags set via callback
        XCTAssertEqual(span.tags["graphql.operation.name"], "GetUser")
        // Default tags still present
        XCTAssertEqual(span.tags[OTTags.httpMethod], "POST")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "200")
        XCTAssertEqual(span.tags[OTTags.spanKind], "client")
    }

    func testGivenNoSpanCustomization_whenInterceptionCompletes_itCreatesSpanNormally() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: nil
        )

        // Given
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
    }

    func testGivenSpanCustomization_whenInterceptionCompletesWithError_itCallsCustomizationWithError() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        var receivedResponse: URLResponse?
        var receivedError: Error?

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: { _, span, response, error in
                receivedResponse = response
                receivedError = error
                span.setTag(key: "custom.error.tag", value: "handled")
            }
        )

        // Given
        let request: ImmutableRequest = .mockWith(
            url: URL(string: "https://www.example.com/api")!,
            httpMethod: "GET"
        )
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: nil, error: networkError)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNil(receivedResponse, "Response should be nil for error-only requests")
        XCTAssertNotNil(receivedError, "Customization callback should receive the error")
        XCTAssertEqual((receivedError as? NSError)?.code, NSURLErrorTimedOut)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags["custom.error.tag"], "handled")
    }

    func testGivenSpanCustomization_whenRequestHasNoBody_itReceivesNilHttpBody() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        var receivedHttpBody: Data? = Data() // non-nil sentinel to detect it was set

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: { request, _, _, _ in
                receivedHttpBody = request.httpBody
            }
        )

        // Given - request with no body
        let request: ImmutableRequest = .mockWith(
            url: URL(string: "https://www.example.com/api")!,
            httpMethod: "GET"
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(receivedHttpBody, "httpBody should be nil when the request has no body")
    }

    func testGivenSpanCustomization_whenMultipleConcurrentRequestsComplete_itSafelyReadsPropertiesFromAllCallbacks() throws {
        // This test simulates multiple URLSession tasks completing simultaneously on different background
        // threads, each triggering `spanCustomization`. It verifies that reading `InterceptedRequest`
        // properties is thread-safe: `url` and `httpMethod` are pre-captured value-type snapshots;
        // `httpBody` is backed by immutable NSData, safe for concurrent reads.
        let concurrentCount = 5
        let allSpansWritten = expectation(description: "All spans written")
        allSpansWritten.expectedFulfillmentCount = concurrentCount
        core.onEventWriteContext = { _ in allSpansWritten.fulfill() }

        var receivedUrls: [URL?] = Array(repeating: nil, count: concurrentCount)
        var receivedMethods: [String?] = Array(repeating: nil, count: concurrentCount)
        var receivedBodies: [Data?] = Array(repeating: nil, count: concurrentCount)
        let lock = NSLock()

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: { request, _, _, _ in
                // Read all InterceptedRequest properties — must be safe from any background thread
                let url = request.url
                let method = request.httpMethod
                let body = request.httpBody
                guard let index = Int(url?.lastPathComponent ?? "") else { return }
                lock.lock()
                receivedUrls[index] = url
                receivedMethods[index] = method
                receivedBodies[index] = body
                lock.unlock()
            }
        )

        // Given - prepare one interception per concurrent "task"
        let interceptions: [URLSessionTaskInterception] = (0..<concurrentCount).map { i in
            let body = "body-\(i)".data(using: .utf8)
            let request: ImmutableRequest = .mockWith(
                url: URL(string: "https://www.example.com/api/\(i)")!,
                httpMethod: "POST",
                httpBody: body
            )
            let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
            interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
            interception.register(
                metrics: .mockWith(
                    fetch: .init(
                        start: .mockDecember15th2019At10AMUTC(),
                        end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                    )
                )
            )
            return interception
        }

        // When - complete all interceptions concurrently from background threads
        // (simulating multiple URLSession tasks finishing simultaneously)
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        for interception in interceptions {
            concurrentQueue.async {
                handler.interceptionDidComplete(interception: interception)
            }
        }

        // Then - all callbacks must complete with correct, non-corrupted property values
        waitForExpectations(timeout: 2.0, handler: nil)
        for i in 0..<concurrentCount {
            XCTAssertEqual(receivedUrls[i]?.absoluteString, "https://www.example.com/api/\(i)")
            XCTAssertEqual(receivedMethods[i], "POST")
            XCTAssertEqual(receivedBodies[i], "body-\(i)".data(using: .utf8))
        }
    }

    func testGivenSpanCustomization_whenDecodingGraphQLBody_itTagsSpanWithOperationName() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "api.example.com": [.datadog]
            ]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry(),
            spanCustomization: { request, span, _, _ in
                // Primary use case: decode GraphQL operation name from request body
                if let body = request.httpBody,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let operationName = json["operationName"] as? String {
                    span.setTag(key: "graphql.operation.name", value: operationName)
                    span.setOperationName("graphql.\(operationName)")
                }
            }
        )

        // Given
        let graphQLBody = #"{"operationName":"GetUser","variables":{"id":"123"}}"#.data(using: .utf8)!
        let request: ImmutableRequest = .mockWith(
            url: URL(string: "https://api.example.com/graphql")!,
            httpMethod: "POST",
            httpBody: graphQLBody
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .registeredDelegate)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "graphql.GetUser")
        XCTAssertEqual(span.tags["graphql.operation.name"], "GetUser")
    }

    private func assert(capturedState: URLSessionHandlerCapturedState?, has span: OTSpan?) {
        guard let state = capturedState as? TracingURLSessionHandler.TracingURLSessionHandlerCapturedState else {
            XCTFail("Expected TracingURLSessionHandlerCapturedState instance, got \(String(describing: capturedState))")
            return
        }

        assertSameDDSpans(state.activeSpan, span)
    }

    private func assertSameDDSpans(_ lhs: OTSpan?, _ rhs: OTSpan?) {
        guard let lSpan = lhs as? DDSpan,
              let rSpan = rhs as? DDSpan,
              lSpan === rSpan
        else {
            XCTFail("Expected spans to be the same DDSpan, got `\(String(describing: lhs))` and `\(String(describing: rhs))`")
            return
        }
    }

    // MARK: - Determinist sampling with child rate correction

    func testDeterministicSamplingForSameSessionID() {
        // Given
        let receiver = ContextMessageReceiver()
        let sessionUUID = "abcdef01-2345-6789-abcd-ef0123456789"
        let sessionSampler = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: 80.0)
        let networkContext = NetworkContext(rumContext: RUMCoreContext(applicationID: "app-id", sessionID: sessionUUID, sessionSampler: sessionSampler))

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: 80.0,
            firstPartyHosts: .init(["example.com": [.datadog]]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        // When — modify is called twice with the same networkContext
        let (_, ctx1, _) = handler.modify(
            request: .mockWith(url: "https://example.com/path"),
            headerTypes: [.datadog],
            networkContext: networkContext
        )
        let (_, ctx2, _) = handler.modify(
            request: .mockWith(url: "https://example.com/path"),
            headerTypes: [.datadog],
            networkContext: networkContext
        )

        // Then — both calls return the same sampling priority (determinism)
        XCTAssertEqual(ctx1?.samplingPriority.isKept, ctx2?.samplingPriority.isKept, "Sampling decision must be deterministic")
    }

    // MARK: Test 2 — Child rate correction (TEST-04)

    func testChildRateCorrectionIsApplied() throws {
        // seed 0xd860b2b9437a (~68.7% hash): NOT sampled at composed 40%, but sampled at trace-only 80%.
        let receiver = ContextMessageReceiver()
        let sessionUUID = "a1b2c3d4-e5f6-7890-abcd-d860b2b9437a"
        let sessionSampleRate: SampleRate = 50.0
        let traceRate: SampleRate = 80.0

        let sessionSampler = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: sessionSampleRate)
        let effectiveRate = sessionSampler.combined(with: traceRate).samplingRate
        XCTAssertEqual(effectiveRate, 40.0, accuracy: 0.001)

        let expectedSampled = sessionSampler.combined(with: traceRate).isSampled
        let oldBehaviour = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: traceRate).isSampled
        XCTAssertNotEqual(expectedSampled, oldBehaviour, "Chosen vector must differ between composed and trace-only rate")

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: traceRate,
            firstPartyHosts: .init(["example.com": [.datadog]]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let (_, traceContext, _) = handler.modify(
            request: .mockWith(url: "https://example.com/resource"),
            headerTypes: [.datadog],
            networkContext: NetworkContext(rumContext: RUMCoreContext(applicationID: "app-id", sessionID: sessionUUID, sessionSampler: sessionSampler))
        )

        let actualSampled = try XCTUnwrap(traceContext?.samplingPriority.isKept)
        XCTAssertEqual(actualSampled, expectedSampled, "Handler must apply child-rate correction via sessionSampler.combined(with:)")
    }

    // MARK: Test 3 — No RUM context fallback

    func testNoRUMContextFallbackDoesNotCrash() {
        // Given — no RUM context in networkContext
        let receiver = ContextMessageReceiver()
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: 80.0,
            firstPartyHosts: .init(["example.com": [.datadog]]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let (_, traceContext, _) = handler.modify(
            request: .mockWith(url: "https://example.com/path"),
            headerTypes: [.datadog],
            networkContext: NetworkContext(rumContext: nil)
        )

        XCTAssertNotNil(traceContext?.samplingPriority.isKept, "Handler must return a sampling decision even without RUM context")
    }

    // MARK: Test 4 — Cross-SDK Knuth vector

    func testCrossSDKKnuthVector() throws {
        let receiver = ContextMessageReceiver()
        // seed 0x8e45571aa876 (~51.2% hash): NOT sampled at composed 48%, but sampled at trace-only 80%.
        let sessionUUID = "a1b2c3d4-e5f6-7890-abcd-8e45571aa876"
        let sessionSampleRate: SampleRate = 60.0
        let traceRate: SampleRate = 80.0

        let sessionSampler = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: sessionSampleRate)
        let effectiveRate = sessionSampler.combined(with: traceRate).samplingRate
        XCTAssertEqual(effectiveRate, 48.0, accuracy: 0.001)

        let expectedSampled = sessionSampler.combined(with: traceRate).isSampled
        let oldBehaviour = DeterministicSampler(uuid: .mockWith(sessionUUID), samplingRate: traceRate).isSampled
        XCTAssertNotEqual(expectedSampled, oldBehaviour, "Chosen vector must differ between composed and trace-only rate")

        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: traceRate,
            firstPartyHosts: .init(["example.com": [.datadog]]),
            traceContextInjection: .all,
            telemetry: NOPTelemetry()
        )

        let (_, traceContext, _) = handler.modify(
            request: .mockWith(url: "https://example.com/resource"),
            headerTypes: [.datadog],
            networkContext: NetworkContext(rumContext: RUMCoreContext(applicationID: "app-id", sessionID: sessionUUID, sessionSampler: sessionSampler))
        )

        let actualSampled = try XCTUnwrap(traceContext?.samplingPriority.isKept)
        XCTAssertEqual(actualSampled, expectedSampled, "Cross-SDK vector: handler must match composed rate Knuth decision")
    }
}
