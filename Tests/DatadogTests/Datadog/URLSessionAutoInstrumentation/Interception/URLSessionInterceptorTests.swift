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
    private lazy var interceptor = URLSessionInterceptor(
        configuration: .mockWith(
            userDefinedFirstPartyHosts: ["first-party.com"],
            sdkInternalURLs: ["https://dd.internal.com"]
        ),
        tracingHandler: tracingHandler,
        rumResourceHandler: rumResourcesHandler
    )
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

    func testGivenTracerRegistered_whenInterceptingURLSessionTasks_itSendsSpanAndRUMResource() throws {
        let interceptor = self.interceptor
        let spanSentExpectation = expectation(description: "Send span for first party request")
        tracingHandler.didSendSpanForInterception = { interception in
            XCTAssertTrue(interception.isDone)
            spanSentExpectation.fulfill()
        }
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
        Global.sharedTracer = Tracer.mockAny()
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

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
        waitForExpectations(timeout: 0.5, handler: nil)

        let tracingInterception = try XCTUnwrap(tracingHandler.interceptionToSendSpan)
        XCTAssertEqual(tracingInterception.request, firstPartyRequest)

        let rumStartResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStartResourceInterceptions.count, 2)
        XCTAssertTrue(rumStartResourceInterceptions.contains { $0.request == firstPartyRequest })
        XCTAssertTrue(rumStartResourceInterceptions.contains { $0.request == thirdPartyRequest })

        let rumStopResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStopResourceInterceptions.count, 2)
        XCTAssertTrue(rumStopResourceInterceptions.contains { $0.request == firstPartyRequest })
        XCTAssertTrue(rumStopResourceInterceptions.contains { $0.request == thirdPartyRequest })
    }

    func testGivenTracerNotRegistered_whenInterceptingURLSessionTasks_itSendsOnlyRUMResources() throws {
        let interceptor = self.interceptor
        let spanNotSentExpectation = expectation(description: "Do not send span")
        spanNotSentExpectation.isInverted = true
        tracingHandler.didSendSpanForInterception = { _ in spanNotSentExpectation.fulfill() }
        let rumResourceStartedExpectation = expectation(description: "Start RUM Resource for first and third party requests")
        rumResourceStartedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStartRUMResourceForInterception = { _ in rumResourceStartedExpectation.fulfill() }
        let rumResourceStoppedExpectation = expectation(description: "Stop RUM Resource for first and third party requests")
        rumResourceStoppedExpectation.expectedFulfillmentCount = 2
        rumResourcesHandler.didStopRUMResourceForInterception = { _ in rumResourceStoppedExpectation.fulfill() }

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

        let rumStartResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStartResourceInterceptions.count, 2)
        XCTAssertTrue(rumStartResourceInterceptions.contains { $0.request == firstPartyRequest })
        XCTAssertTrue(rumStartResourceInterceptions.contains { $0.request == thirdPartyRequest })

        let rumStopResourceInterceptions = rumResourcesHandler.interceptionsForStartingRUMResource
        XCTAssertEqual(rumStopResourceInterceptions.count, 2)
        XCTAssertTrue(rumStopResourceInterceptions.contains { $0.request == firstPartyRequest })
        XCTAssertTrue(rumStopResourceInterceptions.contains { $0.request == thirdPartyRequest })
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
