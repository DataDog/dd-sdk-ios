/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class URLSessionTracingHandlerTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    private let handler = URLSessionTracingHandler(
        appStateListener: AppStateListenerMock(
            history: .init(
                initialSnapshot: .init(state: .active, date: .mockDecember15th2019At10AMUTC()),
                recentDate: .mockDecember15th2019At10AMUTC() + 10
            )
        ),
        tracingSampler: .mockKeepAll()
    )

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(messageReceiver: LogMessageReceiver.mockAny())
        Global.sharedTracer = Tracer.mockWith(core: core)
    }

    override func tearDown() {
        Global.sharedTracer = DDNoopGlobals.tracer
        core = nil
        super.tearDown()
    }

    func testGivenFirstPartyInterceptionWithSpanContext_whenInterceptionCompletes_itUsesInjectedSpanContext() throws {
        core.expectation = expectation(description: "Send span")

        // Given
        let interception = TaskInterception(request: .mockAny(), isFirstParty: true)
        interception.register(completion: .mockAny())
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )
        interception.register(
            spanContext: .mockWith(traceID: 100, spanID: 200, parentSpanID: nil)
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)

        XCTAssertEqual(span.traceID.toString(.decimal), "100")
        XCTAssertEqual(span.spanID.toString(.decimal), "200")
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
        let interception = TaskInterception(request: request, isFirstParty: true)
        interception.register(completion: .mockWith(response: .mockResponseWith(statusCode: 200), error: nil))
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

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
            url: "https://www.example.com",
            queryParams: [
                URLQueryItem(name: "foo", value: "42"),
                URLQueryItem(name: "lang", value: "en")
            ],
            httpMethod: "GET"
        )
        let error = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let interception = TaskInterception(request: request, isFirstParty: true)
        interception.register(completion: .mockWith(response: nil, error: error))
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 30)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.resource, "https://www.example.com")
        XCTAssertEqual(span.duration, 30)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[DDTags.errorType], "domain - 123")
        XCTAssertEqual(
            span.tags[DDTags.errorStack],
            "Error Domain=domain Code=123 \"network error\" UserInfo={NSLocalizedDescription=network error}"
        )
        XCTAssertEqual(span.tags[DDTags.errorMessage], "network error")
        XCTAssertEqual(span.tags.count, 7)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "network error")
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID] as? AnyCodable,
            AnyCodable(span.traceID.toString(.decimal))
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID] as? AnyCodable,
            AnyCodable(span.traceID.toString(.decimal))
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.spanID] as? AnyCodable,
            AnyCodable(span.spanID.toString(.decimal))
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
        let interception = TaskInterception(request: request, isFirstParty: true)
        interception.register(completion: .mockWith(response: .mockResponseWith(statusCode: 404), error: nil))
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

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
        XCTAssertEqual(span.tags[DDTags.errorType], "HTTPURLResponse - 404")
        XCTAssertEqual(span.tags[DDTags.errorMessage], "404 not found")
        XCTAssertEqual(
            span.tags[DDTags.errorStack],
            "Error Domain=HTTPURLResponse Code=404 \"404 not found\" UserInfo={NSLocalizedDescription=404 not found}"
        )
        XCTAssertEqual(span.tags.count, 8)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "404 not found")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.traceID]),
            span.traceID.toString(.decimal)
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?[TracingWithLoggingIntegration.TracingAttributes.spanID]),
            span.spanID.toString(.decimal)
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
        let incompleteInterception = TaskInterception(request: .mockAny(), isFirstParty: true)
        // `incompleteInterception` has no metrics and no completion

        // When
        handler.notify_taskInterceptionCompleted(interception: incompleteInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenThirdPartyInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let interception = TaskInterception(request: .mockAny(), isFirstParty: false)
        interception.register(completion: .mockAny())
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertTrue(core.events.isEmpty)
    }

    func testGivenAnyInterception_itAddsAppStateInformationToSpan() throws {
        core.expectation = expectation(description: "Send span")

        // Given
        let interception = TaskInterception(request: .mockAny(), isFirstParty: true)
        interception.register(completion: .mockAny())
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 10)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.tags[DDTags.foregroundDuration], "10000000000")
        XCTAssertEqual(span.tags[DDTags.isBackground], "false")
    }

    func testGivenRejectingHandler_itDoesNotRecordSpan() throws {
        core.expectation = expectation(description: "Do not send span")
        core.expectation?.isInverted = true

        // Given
        let handler = URLSessionTracingHandler(
            appStateListener: AppStateListenerMock.mockAppInForeground(),
            tracingSampler: .mockRejectAll()
       )

        let interception = TaskInterception(request: .mockAny(), isFirstParty: true)
        interception.register(completion: .mockAny())
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 10)
                )
            )
        )

        // When
        handler.notify_taskInterceptionCompleted(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5)
    }
}
