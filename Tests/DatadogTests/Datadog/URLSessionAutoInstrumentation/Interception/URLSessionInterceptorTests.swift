/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class URLSessionTracingHandlerMock: URLSessionTracingHandlerType {
    var didSendSpanForInterception: ((TaskInterception) -> Void)?
    var interceptionForSendingSpan: TaskInterception?

    func sendSpan(for interception: TaskInterception, using tracer: Tracer) {
        interceptionForSendingSpan = interception
        didSendSpanForInterception?(interception)
    }
}

private class URLSessionRUMResourcesHandlerMock: URLSessionRUMResourcesHandlerType {
    var didStartRUMResourceForInterception: ((TaskInterception) -> Void)?
    var interceptionsForStartingRUMResource: [TaskInterception] = []

    func notify_taskInterceptionStarted(interception: TaskInterception) {
        interceptionsForStartingRUMResource.append(interception)
        didStartRUMResourceForInterception?(interception)
    }

    var didStopRUMResourceForInterception: ((TaskInterception) -> Void)?
    var interceptionsForStoppingRUMResource: [TaskInterception] = []

    func notify_taskInterceptionCompleted(interception: TaskInterception) {
        interceptionsForStoppingRUMResource.append(interception)
        didStopRUMResourceForInterception?(interception)
    }

    func subscribe(commandsSubscriber: RUMCommandSubscriber) {}
}

class URLSessionInterceptorTests: XCTestCase {
    private let tracingHandler = URLSessionTracingHandlerMock()
    private let rumResourcesHandler = URLSessionRUMResourcesHandlerMock()
    /// Mock request made to a first party URL.
    private let firstPartyRequest = URLRequest(url: URL(string: "https://api.first-party.com/v1/endpoint")!)
    /// Mock request made to a third party URL.
    private let thirdPartyRequest = URLRequest(url: URL(string: "https://api.third-party.com/v1/endpoint")!)
    /// Mock request made internally by the SDK (used to test that SDK internal calls to Intake servers are not intercepted).
    private let internalRequest = URLRequest(url: URL(string: "https://dd.internal.com/v1/endpoint")!)

    // MARK: - Initialization

    func testGivenOnlyTracingInstrumentationEnabled_whenInitializing_itRegistersTracingHandler() {
        // Given
        let instrumentTracing = true
        let instrumentRUM = false

        // When
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertNotNil(interceptor.tracingHandler)
        XCTAssertNil(interceptor.rumResourceHandler)
    }

    func testGivenOnlyRUMInstrumentationEnabled_whenInitializing_itRegistersRUMHandler() {
        // Given
        let instrumentTracing = false
        let instrumentRUM = true

        // When
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertNil(interceptor.tracingHandler)
        XCTAssertNotNil(interceptor.rumResourceHandler)
    }

    func testGivenBothTracingAndRUMInstrumentationEnabled_whenInitializing_itRegistersTracingHandlerAndRUMHandler() {
        // Given
        let instrumentTracing = true
        let instrumentRUM = true

        // When
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertNotNil(interceptor.tracingHandler)
        XCTAssertNotNil(interceptor.rumResourceHandler)
    }

    // MARK: - URLRequest Interception

    /// Creates mock interceptor w/ or w/o tracing and RUM handlers.
    private func createInterceptor(
        tracingHandler: URLSessionTracingHandlerType?,
        rumResourceHandler: URLSessionRUMResourcesHandlerType?
    ) -> URLSessionInterceptor {
        return URLSessionInterceptor(
            configuration: .mockWith(
                userDefinedFirstPartyHosts: ["first-party.com"],
                sdkInternalURLs: ["https://dd.internal.com"]
            ),
            tracingHandler: tracingHandler,
            rumResourceHandler: rumResourceHandler
        )
    }

    func testGivenTracingAndRUMHandlersEnabled_whenInterceptingRequests_itInjectsTracingContextToFirstPartyRequests() throws {
        // Given
        let interceptor = createInterceptor(tracingHandler: tracingHandler, rumResourceHandler: rumResourcesHandler)
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertEqual(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField], TracingHTTPHeaders.rumOriginValue)
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])

        XCTAssertNotEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should be modified.")
        XCTAssertEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        XCTAssertEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")

        XCTAssertEqual(
            interceptedFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.traceIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.parentSpanIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.originField),
            firstPartyRequest,
            "The only modification of the original requests should be the addition of 3 tracing headers."
        )
    }

    func testGivenOnlyTracingHandlerEnabled_whenInterceptingRequests_itInjectsTracingContextToFirstPartyRequests() throws {
        // Given
        let interceptor = createInterceptor(tracingHandler: tracingHandler, rumResourceHandler: nil)
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField], "Origin header should not be added if RUM is disabled.")
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])

        XCTAssertNotEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should be modified.")
        XCTAssertEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        XCTAssertEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")

        XCTAssertEqual(
            interceptedFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.traceIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.parentSpanIDField),
            firstPartyRequest,
            "The only modification of the original requests should be the addition of 2 tracing headers."
        )
    }

    func testGivenOnlyRUMHandlerEnabled_whenInterceptingRequests_itDoesNotModifyThem() throws {
        // Given
        let interceptor = createInterceptor(tracingHandler: nil, rumResourceHandler: rumResourcesHandler)
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedThirdPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertNil(interceptedInternalRequest.allHTTPHeaderFields?[TracingHTTPHeaders.originField])

        XCTAssertEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should not be modified.")
        XCTAssertEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        XCTAssertEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenTracingHandlerEnabledButTracerNotRegistered_whenInterceptingRequests_itDoesNotInjectTracingContextToAnyRequest() throws {
        // Given
        let interceptor = createInterceptor(
            tracingHandler: tracingHandler,
            rumResourceHandler: Bool.random() ? rumResourcesHandler : nil
        )
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

    func testGivenTracingAndRUMHandlersEnabled_whenInterceptingURLSessionTasks_itSendsRUMResourceAndNoSpan() throws {
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        tracingHandler.didSendSpanForInterception = { _ in spanNotSentExpectation.fulfill() }
        let rumResourceStartedExpectation = expectation(description: "Start RUM Resource for first and third party requests")
        rumResourceStartedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStartRUMResourceForInterception = { _ in
            rumResourceStartedExpectation.fulfill()
        }
        let rumResourceStoppedExpectation = expectation(description: "Stop RUM Resource for first and third party requests")
        rumResourceStoppedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStopRUMResourceForInterception = { interception in
            XCTAssertTrue(interception.isDone)
            rumResourceStoppedExpectation.fulfill()
        }

        // Given
        let interceptor = createInterceptor(tracingHandler: tracingHandler, rumResourceHandler: rumResourcesHandler)
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: interceptedFirstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: interceptedThirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: interceptedInternalRequest, response: .mockAny())

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
        waitForExpectations(timeout: 0.5, handler: nil)

        // We can't compare entire `URLRequests` in following assertions
        // due to https://openradar.appspot.com/radar?id=4988276943355904

        XCTAssertNil(tracingHandler.interceptionForSendingSpan)

        let rumStartResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStartResourceInterceptions.count, 2)
        XCTAssertTrue(
            rumStartResourceInterceptions.contains { $0.request.url == firstPartyRequest.url && $0.spanContext != nil },
            "RUM Resource should be started and tracing information should be set for 1st party request."
        )
        XCTAssertTrue(
            rumStartResourceInterceptions.contains { $0.request.url == thirdPartyRequest.url && $0.spanContext == nil },
            "RUM Resource should be started but tracing information should NOT be set for 3rd party request."
        )

        let rumStopResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStopResourceInterceptions.count, 2)
        XCTAssertTrue(
            rumStopResourceInterceptions.contains { $0.request.url == firstPartyRequest.url && $0.spanContext != nil },
            "RUM Resource should be stopped and tracing information should be set for 1st party request."
        )
        XCTAssertTrue(
            rumStopResourceInterceptions.contains { $0.request.url == thirdPartyRequest.url && $0.spanContext == nil },
            "RUM Resource should be stopped but tracing information should NOT be set for 3rd party request."
        )
    }

    func testGivenOnlyTracingHandlerEnabled_whenInterceptingURLSessionTasks_itSendsSpan() throws {
        let spanSentExpectation = expectation(description: "Send span for first party request")
        tracingHandler.didSendSpanForInterception = { interception in
            XCTAssertTrue(interception.isDone)
            spanSentExpectation.fulfill()
        }

        // Given
        let interceptor = createInterceptor(tracingHandler: tracingHandler, rumResourceHandler: nil)
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: interceptedFirstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: interceptedThirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: interceptedInternalRequest, response: .mockAny())

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

        // We can't compare entire `URLRequests` in following assertions
        // due to https://openradar.appspot.com/radar?id=4988276943355904

        let tracingInterception = try XCTUnwrap(tracingHandler.interceptionForSendingSpan)
        XCTAssertEqual(
            tracingInterception.request.url,
            firstPartyRequest.url,
            "Span should be send for 1st party request."
        )
        XCTAssertNotNil(tracingInterception.spanContext, "Tracing information should be set for 1st party request.")
    }

    func testGivenOnlyRUMHandlerEnabled_whenInterceptingURLSessionTasks_itSendsRUMResources() throws {
        let rumResourceStartedExpectation = expectation(description: "Start RUM Resource for first and third party requests")
        rumResourceStartedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStartRUMResourceForInterception = { _ in rumResourceStartedExpectation.fulfill() }
        let rumResourceStoppedExpectation = expectation(description: "Stop RUM Resource for first and third party requests")
        rumResourceStoppedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStopRUMResourceForInterception = { _ in rumResourceStoppedExpectation.fulfill() }

        // Given
        let interceptor = createInterceptor(tracingHandler: nil, rumResourceHandler: rumResourcesHandler)

        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: interceptedFirstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: interceptedThirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: interceptedInternalRequest, response: .mockAny())

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

        // We can't compare entire `URLRequests` in following assertions
        // due to https://openradar.appspot.com/radar?id=4988276943355904

        let rumStartResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStartResourceInterceptions.count, 2)
        XCTAssertTrue(
            rumStartResourceInterceptions.contains { $0.request == firstPartyRequest && $0.spanContext == nil },
            "1st party RUM Resource should be started but tracing information should NOT be set."
        )
        XCTAssertTrue(
            rumStartResourceInterceptions.contains { $0.request == thirdPartyRequest && $0.spanContext == nil },
            "3rd party RUM Resource should be started but tracing information should NOT be set."
        )

        let rumStopResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStopResourceInterceptions.count, 2)
        XCTAssertTrue(
            rumStopResourceInterceptions.contains { $0.request == firstPartyRequest && $0.spanContext == nil },
            "1st party RUM Resource should be stopped but tracing information should NOT be set."
        )
        XCTAssertTrue(
            rumStopResourceInterceptions.contains { $0.request == thirdPartyRequest && $0.spanContext == nil },
            "3rd party RUM Resource should be stopped but tracing information should NOT be set."
        )
    }

    // MARK: - Thread Safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let interceptor = createInterceptor(tracingHandler: tracingHandler, rumResourceHandler: rumResourcesHandler)

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
