/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionTracingHandlerTests: XCTestCase {
    private let spanOutput = SpanOutputMock()
    private lazy var tracer = Tracer.mockWith(spanOutput: spanOutput)
    private let handler = URLSessionTracingHandler()

    func testGivenInterceptionWithSpanContext_whenSendingSpan_itUsesInjectedSpanContext() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

        // Given
        var requestWithSpanContext = URLRequest(url: .mockAny())
        requestWithSpanContext.addValue("100", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        requestWithSpanContext.addValue("200", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)

        let interception = TaskInterception(request: requestWithSpanContext)
        interception.register(response: .mockAny(), error: nil)
        interception.register(metrics: .mockWith(taskDuration: 1))

        // When
        handler.sendSpan(for: interception, using: tracer)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.context.dd.traceID.rawValue, 100)
        XCTAssertEqual(span.context.dd.spanID.rawValue, 200)
        XCTAssertEqual(span.operationName, "urlsession.request")
        if #available(iOS 13.0, *) {
            // TODO: RUMM-732 The `URLSessionTaskMetrics` mock is unreliable prior to iOS 13, find different way of asserting the Span duration.
            XCTAssertEqual(spanDuration, 1)
        }
    }

    func testGivenInterceptionWithNoError_whenSendingSpan_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

        // Given
        let request: URLRequest = .mockWith(httpMethod: "POST")
        let interception = TaskInterception(request: request)
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)
        interception.register(metrics: .mockWith(taskDuration: 2))

        // When
        handler.sendSpan(for: interception, using: tracer)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        if #available(iOS 13.0, *) {
            // TODO: RUMM-732 The `URLSessionTaskMetrics` mock is unreliable prior to iOS 13, find different way of asserting the Span duration.
            XCTAssertEqual(spanDuration, 2)
        }
        XCTAssertEqual(span.tags[DDTags.resource] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpUrl] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod] as? String, "POST")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode] as? Int, 200)
        XCTAssertEqual(span.tags.count, 4)
    }

    func testGivenInterceptionWithNetworkError_whenSendingSpan_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

        // Given
        let request: URLRequest = .mockWith(httpMethod: "GET")
        let error = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let interception = TaskInterception(request: request)
        interception.register(response: nil, error: error)
        interception.register(metrics: .mockWith(taskDuration: 30))

        // When
        handler.sendSpan(for: interception, using: tracer)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        if #available(iOS 13.0, *) {
            // TODO: RUMM-732 The `URLSessionTaskMetrics` mock is unreliable prior to iOS 13, find different way of asserting the Span duration.
            XCTAssertEqual(spanDuration, 30)
        }
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

    func testGivenInterceptionWithServerError_whenSendingSpan_itEncodesRequestInfoInSpan() throws {
        let spanSentExpectation = expectation(description: "Send span")
        spanOutput.onSpanRecorded = { _ in spanSentExpectation.fulfill() }

        // Given
        let request: URLRequest = .mockWith(httpMethod: "GET")
        let interception = TaskInterception(request: request)
        interception.register(response: .mockResponseWith(statusCode: 404), error: nil)
        interception.register(metrics: .mockWith(taskDuration: 2))

        // When
        handler.sendSpan(for: interception, using: tracer)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let span = try XCTUnwrap(spanOutput.recorded?.span)
        let spanDuration = spanOutput.recorded?.finishTime.timeIntervalSince(span.startTime)
        XCTAssertEqual(span.operationName, "urlsession.request")
        if #available(iOS 13.0, *) {
            // TODO: RUMM-732 The `URLSessionTaskMetrics` mock is unreliable prior to iOS 13, find different way of asserting the Span duration.
            XCTAssertEqual(spanDuration, 2)
        }
        XCTAssertEqual(span.tags[DDTags.resource] as? String, "404")
        XCTAssertEqual(span.tags[OTTags.httpUrl] as? String, request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod] as? String, "GET")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode] as? Int, 404)
        XCTAssertEqual(span.tags[OTTags.error] as? Bool, true)
        XCTAssertEqual(span.tags.count, 5)
    }

    func testGivenIncompleteInterception_itDoesNotSendTheSpan() throws {
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        spanOutput.onSpanRecorded = { _ in spanNotSentExpectation.fulfill() }

        // Given
        let incompleteInterception = TaskInterception(request: .mockAny())
        // `incompleteInterception` has no metrics and no completion

        // When
        handler.sendSpan(for: incompleteInterception, using: tracer)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(spanOutput.recorded?.span)
    }
}
