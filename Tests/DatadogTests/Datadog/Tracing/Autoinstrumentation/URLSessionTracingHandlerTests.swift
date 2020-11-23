/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionTracingHandlerTests: XCTestCase {
    private let spanOutput = SpanOutputMock()
    private let handler = URLSessionTracingHandler()

    override func setUp() {
        Global.sharedTracer = Tracer.mockWith(spanOutput: spanOutput)
        super.setUp()
    }

    override func tearDown() {
        Global.sharedTracer = DDNoopGlobals.tracer
        super.tearDown()
    }

    func testGivenFirstPartyInterceptionWithSpanContext_whenInterceptionCompletes_itUsesInjectedSpanContext() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

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

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.context.dd.traceID.rawValue, 100)
        XCTAssertEqual(span.context.dd.spanID.rawValue, 200)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(spanDuration, 1)
    }

    func testGivenFirstPartyInterceptionWithNoError_whenInterceptionCompletes_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

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

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(spanDuration, 2)
        XCTAssertEqual(span.tags[DDTags.resource] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpUrl] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod] as? String, "POST")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode] as? Int, 200)
        XCTAssertEqual(span.tags.count, 4)
    }

    func testGivenFirstPartyInterceptionWithNetworkError_whenInterceptionCompletes_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

        // Given
        let request: URLRequest = .mockWith(httpMethod: "GET")
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

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(spanDuration, 30)
        XCTAssertEqual(span.tags[DDTags.resource] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpUrl] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod] as? String, "GET")
        XCTAssertEqual(span.tags[OTTags.error] as? Bool, true)
        XCTAssertEqual(span.tags[DDTags.errorType] as? String, "domain - 123")
        XCTAssertEqual(span.tags[DDTags.errorMessage] as? String, "network error")
        XCTAssertEqual(
            span.tags[DDTags.errorStack] as? String,
            #"Error Domain=domain Code=123 "network error" UserInfo={NSLocalizedDescription=network error}"#
        )
        XCTAssertEqual(span.tags.count, 7)
    }

    func testGivenFirstPartyInterceptionWithServerError_whenInterceptionCompletes_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

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

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(spanDuration, 2)
        XCTAssertEqual(span.tags[DDTags.resource] as? String, "404")
        XCTAssertEqual(span.tags[OTTags.httpUrl] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod] as? String, "GET")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode] as? Int, 404)
        XCTAssertEqual(span.tags[OTTags.error] as? Bool, true)
        XCTAssertEqual(span.tags.count, 5)
    }

    func testGivenFirstPartyIncompleteInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        spanOutput.onSpanRecorded = { _ in spanNotSentExpectation.fulfill() }

        // Given
        let incompleteInterception = TaskInterception(request: .mockAny(), isFirstParty: true)
        // `incompleteInterception` has no metrics and no completion

        // When
        handler.notify_taskInterceptionCompleted(interception: incompleteInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(spanOutput.recorded?.span)
    }

    func testGivenThirdPartyInterception_whenInterceptionCompletes_itDoesNotSendTheSpan() throws {
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        spanOutput.onSpanRecorded = { _ in spanNotSentExpectation.fulfill() }

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
        XCTAssertNil(spanOutput.recorded?.span)
    }
}
