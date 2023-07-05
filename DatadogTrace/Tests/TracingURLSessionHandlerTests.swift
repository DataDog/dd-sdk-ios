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
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: true)
        core = PassthroughCoreMock(messageReceiver: receiver)

        tracer = .mockWith(
            core: core,
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
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
            contextReceiver: ContextMessageReceiver(bundleWithRumEnabled: true),
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
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.traceIDField), "00000000000000000000000000000001")
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.spanIDField), "0000000000000001")
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.sampledField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Single.b3Field), "00000000000000000000000000000001-0000000000000001-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000001-01")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectTraceHeaders() throws {
        // Given
        let handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(bundleWithRumEnabled: true),
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
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.sampledField), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Single.b3Field), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000001-00")
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
        interception.register(traceID: 100, spanID: 200, parentSpanID: nil)

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
        let request: URLRequest = .mockWith(httpMethod: "POST")
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
        var request: URLRequest = .mockAny()
        request.setValue("rum", forHTTPHeaderField: TracingHTTPHeaders.originField)
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
        let receiver = ContextMessageReceiver(bundleWithRumEnabled: true)

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
