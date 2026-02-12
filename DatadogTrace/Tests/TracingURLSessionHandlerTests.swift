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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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

        let (request, _, capturedState) = handler.modify(
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
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

    // MARK: - Baggage Header Merging Tests

    func testGivenRequestWithExistingBaggageHeader_whenTraceContextIsInjected_itMergesBaggageHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: TelemetryMock()
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        request.setValue("custom.key=custom.value,another.key=another.value", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _, _) = handler.modify(
            request: request,
            headerTypes: [.datadog],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Verify that both existing and new baggage values are present
        XCTAssertTrue(baggageHeader?.contains("custom.key=custom.value") == true)
        XCTAssertTrue(baggageHeader?.contains("another.key=another.value") == true)
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
    }

    func testGivenRequestWithExistingBaggageHeader_whenTraceContextIsInjectedWithW3C_itMergesBaggageHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: TelemetryMock()
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        request.setValue("custom.key=custom.value,session.id=old.session.id", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Verify that existing custom key is preserved
        XCTAssertTrue(baggageHeader?.contains("custom.key=custom.value") == true)
        // Verify that session.id is overridden with new value
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
    }

    func testGivenRequestWithComplexBaggageHeader_whenTraceContextIsInjected_itMergesBaggageHeadersCorrectly() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: TelemetryMock()
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        // This is a complex scenario with whitespace and semicolons in values
        request.setValue(" toto=1,car= Dacia Sandero ,session.id = 2,testProp=1; testProp2=4;prop3 ", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                ),
                userConfigurationContext: .init(id: "user123"),
                accountConfigurationContext: .init(id: "account456")
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Parse the result to verify merging behavior
        let baggageDict = extractBaggageKeyValuePairs(from: baggageHeader!)

        // Verify that new values override previous ones
        XCTAssertEqual(baggageDict["session.id"], "abcdef01-2345-6789-abcd-ef0123456789")

        // Verify that previous values are preserved when not overridden
        XCTAssertEqual(baggageDict["toto"], "1")
        XCTAssertEqual(baggageDict["car"], "Dacia Sandero")
        XCTAssertEqual(baggageDict["testProp"], "1; testProp2=4;prop3") // Everything after first = is value

        // Verify that new values are added
        XCTAssertEqual(baggageDict["account.id"], "account456")
        XCTAssertEqual(baggageDict["user.id"], "user123")

        // Verify all expected keys are present
        XCTAssertEqual(baggageDict.keys.count, 6)
    }

    func testGivenRequestWithNoBaggageHeader_whenTraceContextIsInjected_itSetsBaggageHeader() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init(),
            traceContextInjection: .all,
            telemetry: TelemetryMock()
        )

        let request = URLRequest.mockWith(url: "https://www.example.com")

        // When
        let (modifiedRequest, _, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
    }

    // MARK: - Helper Methods

    private func extractBaggageKeyValuePairs(from header: String) -> [String: String] {
        var dict: [String: String] = [:]
        let fields = header.split(separator: ",")

        for field in fields {
            let fieldString = String(field)
            if let equalIndex = fieldString.firstIndex(of: "=") {
                let key = fieldString[..<equalIndex].trimmingCharacters(in: .whitespaces)
                let value = fieldString[fieldString.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    dict[key] = value
                }
            }
        }

        return dict
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
}
