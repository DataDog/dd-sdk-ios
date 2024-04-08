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
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 1)
        )

        handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ])
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
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init()
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "2")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "00000000000000000000000000000001")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000002")
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "00000000000000000000000000000001-0000000000000002-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000002-01")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itDoesNotOverwriteTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init()
        )

        // When
        var request: URLRequest = .mockWith(url: "https://www.example.com")
        request.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        request.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)
        request.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField)
        request.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField)
        request.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField)
        request.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField)
        request.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField)
        request.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Single.b3Field)
        request.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.traceparent)

        request = handler.modify(
            request: request,
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "custom")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            tracingSampler: .mockRejectAll(),
            firstPartyHosts: .init()
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000002-00")
    }

    func testGivenFirstPartyInterception_withActiveSpan_itInjectParentSpanID() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(),
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init()
        )

        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ]
        )

        span.finish()

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "3")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "00000000000000000000000000000001")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000003")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "0000000000000002")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "00000000000000000000000000000001-0000000000000003-1-0000000000000002")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000003-01")
    }

    func testGivenFirstPartyInterceptionWithSpanContext_whenInterceptionCompletes_itUsesInjectedSpanContext() throws {
        core.expectation = expectation(description: "Send span")

        // Given
        let interception = URLSessionTaskInterception(
            request: .mockAny(),
            isFirstParty: true
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
            parentSpanID: nil
        ))

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)

        XCTAssertEqual(String(span.traceID), "100")
        XCTAssertEqual(String(span.spanID), "200")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.duration, 1)
    }

    func testGivenFirstPartyInterceptionWithNoError_whenInterceptionCompletes_itEncodesRequestInfoInSpan() throws {
        core.expectation = expectation(description: "Send span")

        // Given
        let request: ImmutableRequest = .mockWith(httpMethod: "POST")
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true)
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
        XCTAssertEqual(span.tags.count, 5)
    }

    func testTraceContext_whenInterceptionStarts_withActiveSpan_itReturnCurrentSpan() {
        // When
        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()
        // Then
        let context = handler.traceContext()
        XCTAssertEqual(context?.traceID, TraceID(rawValue: 1))
        XCTAssertEqual(context?.spanID, SpanID(rawValue: 2))

        // When
        span.finish()
        // Then
        XCTAssertNil(handler.traceContext())
    }

    func testGivenFirstPartyInterception_whenInterceptionStarts_withActiveSpan_itSendParentSpanID() throws {
        core.expectation = expectation(description: "Send span")
        core.expectation?.expectedFulfillmentCount = 2

        // Given
        let request: ImmutableRequest = .mockWith(httpMethod: "POST")
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true)

        // When
        let span = tracer.startRootSpan(operationName: "root")
        span.setActive()
        interception.register(trace: TraceContext(
            traceID: span.context.dd.traceID,
            spanID: SpanID(rawValue: 3),
            parentSpanID: span.context.dd.spanID
        ))
        handler.interceptionDidStart(interception: interception)
        // Then
        XCTAssertEqual(interception.trace?.parentSpanID?.rawValue, 2)

        // When
        span.finish()
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelopes: [SpanEventsEnvelope] = core.events()
        let event1 = try XCTUnwrap(envelopes.first?.spans.first)
        XCTAssertEqual(event1.operationName, "root")
        XCTAssertEqual(event1.traceID, TraceID(rawValue: 1))
        XCTAssertEqual(event1.spanID, SpanID(rawValue: 2))
        XCTAssertNil(event1.parentID)
        let event2 = try XCTUnwrap(envelopes.last?.spans.first)
        XCTAssertEqual(event2.operationName, "urlsession.request")
        XCTAssertEqual(event2.traceID, TraceID(rawValue: 1))
        XCTAssertEqual(event2.parentID, SpanID(rawValue: 2))
        XCTAssertEqual(event2.spanID, SpanID(rawValue: 3))
    }

    func testGivenFirstPartyIncompleteInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let incompleteInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true)
        // `incompleteInterception` has no metrics and no completion

        // When
        handler.interceptionDidComplete(interception: incompleteInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenThirdPartyInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: false)
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

    func testRUM2APMInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let request: ImmutableRequest = .mockWith(
            allHTTPHeaderFields: [TracingHTTPHeaders.originField: "rum"]
        )
        let interception = URLSessionTaskInterception(request: request, isFirstParty: false)
        interception.register(response: .mockAny(), error: nil)

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenAnyInterception_itAddsAppStateInformationToSpan() throws {
        core.expectation = expectation(description: "Send span")

        // Given
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true)
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
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let receiver = ContextMessageReceiver()

        let handler = TracingURLSessionHandler(
            tracer: .mockWith(core: core),
            contextReceiver: receiver,
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init()
        )

        core.context.applicationStateHistory = .mockAppInForeground()

        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true)
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
}
