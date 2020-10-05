/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class URLSessionTracingHandlerMock: URLSessionTracingHandlerType {
    var didSendSpanForInterception: ((TaskInterception) -> Void)?
    var interceptionToSendSpan: TaskInterception?

    func sendSpan(for interception: TaskInterception, using tracer: Tracer) {
        interceptionToSendSpan = interception
        didSendSpanForInterception?(interception)
    }
}

class URLSessionInterceptorTests: XCTestCase {
    private let tracingHandler = URLSessionTracingHandlerMock()
    private lazy var interceptor = URLSessionInterceptor(
        configuration: .mockWith(
            userDefinedFirstPartyHosts: ["first-party.com"],
            sdkInternalURLs: ["https://dd.internal.com"]
        ),
        tracingInterceptionHandler: tracingHandler
    )
    /// Mock request made to a first party URL.
    private let firstPartyRequest = URLRequest(url: URL(string: "https://api.first-party.com/v1/endpoint")!)
    /// Mock request made to a third party URL.
    private let thirdPartyRequest = URLRequest(url: URL(string: "https://api.third-party.com/v1/endpoint")!)
    /// Mock request made internally by the SDK (used to test that SDK internal calls to Intake servers are not intercepted).
    private let internalRequest = URLRequest(url: URL(string: "https://dd.internal.com/v1/endpoint")!)

    // MARK: - URLRequest Interception

    func testGivenTracerRegistered_whenInterceptingRequests_itInjectsSpanContextOnlyToFirstPartyRequests() throws {
        // Given
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])

        XCTAssertNotEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should be modified.")
        XCTAssertEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        XCTAssertEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenTracerNotRegistered_whenInterceptingRequests_itDoesNotInjectSpanContextToAnyRequest() throws {
        // Given
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should not be modified.")
        XCTAssertEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        XCTAssertEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    // MARK: - URLSessionTask Interception

    func testGivenTracerRegistered_whenInterceptingURLSessionTasks_itSendsSpanOnlyForFirstPartyRequests() throws {
        let interceptor = self.interceptor
        let spanSentExpectation = expectation(description: "Send span for first party request")
        tracingHandler.didSendSpanForInterception = { _ in spanSentExpectation.fulfill() }

        // Given
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let firstPartyTaskResponse: HTTPURLResponse = .mockAny()
        let firstPartyTaskMetrics: URLSessionTaskMetrics = .mockWith(taskInterval: .init(start: Date(), duration: 1))
        let firstPartyTaskError = ErrorMock("1st party task error")
        let firstPartyTask: URLSessionTask = .mockWith(request: firstPartyRequest, response: firstPartyTaskResponse)

        let thirdPartyTaskResponse: HTTPURLResponse = .mockAny()
        let thirdPartyTaskMetrics: URLSessionTaskMetrics = .mockWith(taskInterval: .init(start: Date(), duration: 2))
        let thirdPartyTaskError = ErrorMock("3rd party task error")
        let thirdPartyTask: URLSessionTask = .mockWith(request: thirdPartyRequest, response: thirdPartyTaskResponse)

        let internalTaskResponse: HTTPURLResponse = .mockAny()
        let internalTaskMetrics: URLSessionTaskMetrics = .mockWith(taskInterval: .init(start: Date(), duration: 2))
        let internalTaskError = ErrorMock("internal task error")
        let internalTask: URLSessionTask = .mockWith(request: internalRequest, response: internalTaskResponse)

        // swiftlint:disable opening_brace
        callConcurrently(
            { interceptor.taskCreated(urlSession: .mockAny(), task: firstPartyTask) },
            { interceptor.taskCreated(urlSession: .mockAny(), task: thirdPartyTask) },
            { interceptor.taskCreated(urlSession: .mockAny(), task: internalTask) }
        )
        callConcurrently(
            { interceptor.taskCompleted(urlSession: .mockAny(), task: firstPartyTask, error: firstPartyTaskError) },
            { interceptor.taskCompleted(urlSession: .mockAny(), task: thirdPartyTask, error: thirdPartyTaskError) },
            { interceptor.taskCompleted(urlSession: .mockAny(), task: internalTask, error: internalTaskError) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: firstPartyTask, metrics: firstPartyTaskMetrics) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: thirdPartyTask, metrics: thirdPartyTaskMetrics) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: internalTask, metrics: internalTaskMetrics) }
        )
        // swiftlint:enable opening_brace

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let interception = try XCTUnwrap(tracingHandler.interceptionToSendSpan)
        XCTAssertEqual(interception.request, firstPartyRequest)
        XCTAssertTrue(interception.completion?.httpResponse === firstPartyTaskResponse)
        XCTAssertEqual((interception.completion?.error as? ErrorMock)?.description, "1st party task error")
        XCTAssertEqual(interception.metrics!.fetch.start, firstPartyTaskMetrics.taskInterval.start)
        XCTAssertEqual(interception.metrics!.fetch.end, firstPartyTaskMetrics.taskInterval.end)
    }

    func testGivenTracerNotRegistered_whenInterceptingURLSessionTasks_itDoesNotSendsSpanForAnyRequest() throws {
        let interceptor = self.interceptor
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        tracingHandler.didSendSpanForInterception = { _ in spanNotSentExpectation.fulfill() }

        // Given
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: firstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: thirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: internalRequest, response: .mockAny())

        // swiftlint:disable opening_brace
        callConcurrently(
            { interceptor.taskCreated(urlSession: .mockAny(), task: firstPartyTask) },
            { interceptor.taskCreated(urlSession: .mockAny(), task: thirdPartyTask) },
            { interceptor.taskCreated(urlSession: .mockAny(), task: internalTask) }
        )
        callConcurrently(
            { interceptor.taskCompleted(urlSession: .mockAny(), task: firstPartyTask, error: nil) },
            { interceptor.taskCompleted(urlSession: .mockAny(), task: thirdPartyTask, error: nil) },
            { interceptor.taskCompleted(urlSession: .mockAny(), task: internalTask, error: nil) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: firstPartyTask, metrics: .mockAny()) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: thirdPartyTask, metrics: .mockAny()) },
            { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: internalTask, metrics: .mockAny()) }
        )
        // swiftlint:enable opening_brace

        // Then
        waitForExpectations(timeout: 0.25, handler: nil)

        XCTAssertNil(tracingHandler.interceptionToSendSpan)
    }

    // MARK: - Thread Safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let interceptor = self.interceptor

        let requests = [firstPartyRequest, thirdPartyRequest, internalRequest]
        let tasks = (0..<10).map { _ in URLSessionTask.mockWith(request: .mockAny(), response: .mockAny()) }

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = interceptor.modify(request: requests.randomElement()!) },
                { interceptor.taskCreated(urlSession: .mockAny(), task: tasks.randomElement()!) },
                { interceptor.taskMetricsCollected(urlSession: .mockAny(), task: tasks.randomElement()!, metrics: .mockAny()) },
                { interceptor.taskCompleted(urlSession: .mockAny(), task: tasks.randomElement()!, error: nil) }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace
    }
}
