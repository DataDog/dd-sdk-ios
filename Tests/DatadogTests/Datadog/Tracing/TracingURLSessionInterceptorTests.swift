/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogLogs
@testable import Datadog

class TracingURLSessionInterceptorTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var core: PassthroughCoreMock!
    var tracer: DatadogTracer!
    var interceptor: TracingURLSessionHandler!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        let receiver = ContextMessageReceiver(bundleWithRUM: true)
        core = PassthroughCoreMock(messageReceiver: CombinedFeatureMessageReceiver([
            LogMessageReceiver.mockAny(),
            receiver
        ]))

        tracer = .mockWith(
            core: core,
            tracingUUIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
        )

        interceptor = TracingURLSessionHandler(
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
        let interceptor = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(bundleWithRUM: true),
            tracingSampler: .mockKeepAll(),
            firstPartyHosts: .init()
        )

        // When
        let request = interceptor.modify(
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
        let interceptor = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: ContextMessageReceiver(bundleWithRUM: true),
            tracingSampler: .mockRejectAll(),
            firstPartyHosts: .init()
        )

        // When
        let request = interceptor.modify(
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
        interceptor.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)

        XCTAssertEqual(String(span.traceID), "100")
        XCTAssertEqual(String(span.spanID), "200")
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.duration, 1)

        let log: LogEvent? = core.events().last
        XCTAssertNil(log)
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
        interceptor.interceptionDidComplete(interception: interception)

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

        let log: LogEvent? = core.events().last
        XCTAssertNil(log)
    }

    func testGivenFirstPartyInterceptionWithNetworkError_whenInterceptionCompletes_itEncodesRequestInfoInSpanAndSendsLog() throws {
        core.expectation = expectation(description: "Send span and log")
        core.expectation?.expectedFulfillmentCount = 2

        // Given
        let request: URLRequest = .mockWith(
            url: "http://www.example.com",
            queryParams: [
                URLQueryItem(name: "foo", value: "42"),
                URLQueryItem(name: "lang", value: "en")
            ],
            httpMethod: "GET"
        )
        let error = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true)
        interception.register(response: nil, error: error)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 30)
                )
            )
        )

        // When
        interceptor.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.resource, "http://www.example.com")
        XCTAssertEqual(span.duration, 30)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[DatadogSpanTag.errorType], "domain - 123")
        XCTAssertEqual(
            span.tags[DatadogSpanTag.errorStack],
            "Error Domain=domain Code=123 \"network error\" UserInfo={NSLocalizedDescription=network error}"
        )
        XCTAssertEqual(span.tags[DatadogSpanTag.errorMessage], "network error")
        XCTAssertEqual(span.tags.count, 7)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "network error")
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID] as? AnyCodable,
            AnyCodable(String(span.traceID))
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID] as? AnyCodable,
            AnyCodable(String(span.traceID))
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.spanID] as? AnyCodable,
            AnyCodable(String(span.spanID))
        )
        XCTAssertEqual(log.error?.kind, "domain - 123")
        XCTAssertEqual(log.attributes.internalAttributes?.count, 2)
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes[OTLogFields.event]),
            "error"
        )
        XCTAssertEqual(
            log.error?.stack,
            "Error Domain=domain Code=123 \"network error\" UserInfo={NSLocalizedDescription=network error}"
        )
        XCTAssertEqual(log.attributes.userAttributes.count, 1)
    }

    func testGivenFirstPartyInterceptionWithClientError_whenInterceptionCompletes_itEncodesRequestInfoInSpanAndSendsLog() throws {
        core.expectation = expectation(description: "Send span and log")
        core.expectation?.expectedFulfillmentCount = 2

        // Given
        let request: URLRequest = .mockWith(httpMethod: "GET")
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true)
        interception.register(response: .mockResponseWith(statusCode: 404), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )

        // When
        interceptor.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.resource, "404")
        XCTAssertEqual(span.duration, 2)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "404")
        XCTAssertEqual(span.tags[DatadogSpanTag.errorType], "HTTPURLResponse - 404")
        XCTAssertEqual(span.tags[DatadogSpanTag.errorMessage], "404 not found")
        XCTAssertEqual(
            span.tags[DatadogSpanTag.errorStack],
            "Error Domain=HTTPURLResponse Code=404 \"404 not found\" UserInfo={NSLocalizedDescription=404 not found}"
        )
        XCTAssertEqual(span.tags.count, 8)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "404 not found")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID]),
            String(span.traceID)
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.spanID]),
            String(span.spanID)
        )
        XCTAssertEqual(log.error?.kind, "HTTPURLResponse - 404")
        XCTAssertEqual(log.attributes.internalAttributes?.count, 2)
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes[OTLogFields.event]),
            "error"
        )
        XCTAssertEqual(
            log.error?.stack,
            "Error Domain=HTTPURLResponse Code=404 \"404 not found\" UserInfo={NSLocalizedDescription=404 not found}"
        )
        XCTAssertEqual(log.attributes.userAttributes.count, 1)
    }

    func testGivenFirstPartyIncompleteInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let incompleteInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: true)
        // `incompleteInterception` has no metrics and no completion

        // When
        interceptor.interceptionDidComplete(interception: incompleteInterception)

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
        interceptor.interceptionDidComplete(interception: interception)

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
        interceptor.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.tags[DatadogSpanTag.foregroundDuration], "10000000000")
        XCTAssertEqual(span.tags[DatadogSpanTag.isBackground], "false")
    }

    func testGivenRejectingHandler_itDoesNotRecordSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let receiver = ContextMessageReceiver(bundleWithRUM: true)

        let interceptor = TracingURLSessionHandler(
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
        interceptor.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5)
    }
}
