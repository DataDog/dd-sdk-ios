/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class URLSessionInterceptorTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    private let handler = URLSessionInterceptionHandlerMock()
    /// Mock request made to a first party URL.
    private let firstPartyRequest = URLRequest(url: URL(string: "https://api.first-party.com/v1/endpoint")!)
    /// Alternative mock request made to a first party URL.
    private let alternativeFirstPartyRequest = URLRequest(url: URL(string: "https://api.another-first-party.com/v1/endpoint")!)
    /// Mock request made to a third party URL.
    private let thirdPartyRequest = URLRequest(url: URL(string: "https://api.third-party.com/v1/endpoint")!)
    /// Mock request made internally by the SDK (used to test that SDK internal calls to Intake servers are not intercepted).
    private let internalRequest = URLRequest(url: URL(string: "https://dd.internal.com/v1/endpoint")!)

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock()
        core.register(feature: TracingFeature.mockWith())
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testGivenOnlyTracingInstrumentationEnabled_whenInitializing_itRegistersTracingHandler() throws {
        // Given
        let instrumentTracing = true
        let instrumentRUM = false

        // When
        let appStateListener = AppStateListenerMock.mockAny()
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider(),
            appStateListener: appStateListener
        )

        // Then
        let tracingHandler = try XCTUnwrap(interceptor.handler as? URLSessionTracingHandler)
        XCTAssert(tracingHandler.appStateListener === appStateListener)
        XCTAssertTrue(
            interceptor.injectTracingHeadersToFirstPartyRequests,
            "Tracing headers should be injected when only Tracing instrumentation is enabled."
        )
        XCTAssertNil(
            interceptor.datadogOriginHeader,
            "Just the tracing headers should be injected when only Tracing instrumentation is enabled."
        )
    }

    func testGivenOnlyRUMInstrumentationEnabled_whenInitializing_itRegistersRUMHandler() {
        // Given
        let instrumentTracing = false
        let instrumentRUM = true

        // When
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListenerMock.mockAny()
        )

        // Then
        XCTAssertTrue(interceptor.handler is URLSessionRUMResourcesHandler)
        XCTAssertFalse(
            interceptor.injectTracingHeadersToFirstPartyRequests,
            "Tracing headers should not be injected when only RUM instrumentation is enabled."
        )
        XCTAssertNil(
            interceptor.datadogOriginHeader,
            "No additional headers should be injected when only RUM instrumentation is enabled."
        )
    }

    func testGivenBothTracingAndRUMInstrumentationEnabled_whenInitializing_itRegistersRUMHandler() {
        // Given
        let instrumentTracing = true
        let instrumentRUM = true

        // When
        let interceptor = URLSessionInterceptor(
            configuration: .mockWith(instrumentTracing: instrumentTracing, instrumentRUM: instrumentRUM),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListenerMock.mockAny()
        )

        // Then
        XCTAssertTrue(interceptor.handler is URLSessionRUMResourcesHandler)
        XCTAssertTrue(
            interceptor.injectTracingHeadersToFirstPartyRequests,
            "Tracing headers should be injected when both Tracing and RUM instrumentations are enabled."
        )
        XCTAssertEqual(
            interceptor.datadogOriginHeader?.field,
            TracingHTTPHeaders.ddOrigin.field,
            "Additional `x-datadog-origin` header field should be injected when both Tracing and RUM instrumentations are enabled."
        )
        XCTAssertEqual(
            interceptor.datadogOriginHeader?.value,
            TracingHTTPHeaders.ddOrigin.value,
            "Additional `rum` header value should be injected when both Tracing and RUM instrumentations are enabled."
        )
    }

    // MARK: - URLRequest Interception

    private func mockConfiguration(
        tracingInstrumentationEnabled: Bool,
        rumInstrumentationEnabled: Bool,
        tracingSampler: Sampler = .mockKeepAll()
    ) -> FeaturesConfiguration.URLSessionAutoInstrumentation {
        return .mockWith(
            userDefinedFirstPartyHosts: .init(["first-party.com": [.datadog]]),
            sdkInternalURLs: ["https://dd.internal.com"],
            instrumentTracing: tracingInstrumentationEnabled,
            instrumentRUM: rumInstrumentationEnabled,
            tracingSampler: tracingSampler
        )
    }

    func testGivenTracingAndRUMInstrumentationEnabled_whenInterceptingRequests_itInjectsTracingContextToFirstPartyRequests() throws {
        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(
                tracingInstrumentationEnabled: true,
                rumInstrumentationEnabled: true,
                tracingSampler: .mockKeepAll()
            ),
            handler: handler
        )
        Global.sharedTracer = Tracer.mockAny(in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }
        let sessionWithCustomFirstPartyHosts = URLSession.mockWith(
            DDURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [alternativeFirstPartyRequest.url!.host!: [.datadog]])
        )

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)
        let interceptedCustomFirstPartyRequest = interceptor.modify(
            request: alternativeFirstPartyRequest,
            session: sessionWithCustomFirstPartyHosts
        )

        // Then
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertEqual(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.samplingPriorityField], "1")
        XCTAssertEqual(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.ddOrigin.field], TracingHTTPHeaders.ddOrigin.value)
        assertRequestsEqual(
            interceptedFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.traceIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.parentSpanIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.samplingPriorityField)
                .removing(httpHeaderField: TracingHTTPHeaders.ddOrigin.field),
            firstPartyRequest,
            "The only modification of the original requests should be the addition of 4 tracing headers."
        )

        XCTAssertNotNil(interceptedCustomFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedCustomFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertEqual(interceptedCustomFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.samplingPriorityField], "1")
        XCTAssertEqual(interceptedCustomFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.ddOrigin.field], TracingHTTPHeaders.ddOrigin.value)
        assertRequestsEqual(
            interceptedCustomFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.traceIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.parentSpanIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.samplingPriorityField)
                .removing(httpHeaderField: TracingHTTPHeaders.ddOrigin.field),
            alternativeFirstPartyRequest,
            "The only modification of the original requests should be the addition of 4 tracing headers."
        )

        assertRequestsEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        assertRequestsEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenOnlyTracingInstrumentationEnabled_whenInterceptingRequests_itInjectsTracingContextToFirstPartyRequests() throws {
        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(
                tracingInstrumentationEnabled: true,
                rumInstrumentationEnabled: false,
                tracingSampler: .mockKeepAll()
            ),
            handler: handler
        )
        Global.sharedTracer = Tracer.mockAny(in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNotNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertEqual(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.samplingPriorityField], "1")
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.ddOrigin.field], "Origin header should not be added if RUM is disabled.")
        assertRequestsEqual(
            interceptedFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.traceIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.parentSpanIDField)
                .removing(httpHeaderField: TracingHTTPHeaders.samplingPriorityField),
            firstPartyRequest,
            "The only modification of the original requests should be the addition of 4 tracing headers."
        )
        assertRequestsEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        assertRequestsEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenTracingInstrumentationEnabled_whenInterceptingRequests_itInjectsSampledOutTracingContextToFirstPartyRequests() throws {
        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(
                tracingInstrumentationEnabled: true,
                rumInstrumentationEnabled: false,
                tracingSampler: .mockRejectAll()
            ),
            handler: handler
        )
        Global.sharedTracer = Tracer.mockAny(in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.traceIDField])
        XCTAssertNil(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.parentSpanIDField])
        XCTAssertEqual(interceptedFirstPartyRequest.allHTTPHeaderFields?[TracingHTTPHeaders.samplingPriorityField], "0")
        assertRequestsEqual(
            interceptedFirstPartyRequest
                .removing(httpHeaderField: TracingHTTPHeaders.samplingPriorityField),
            firstPartyRequest,
            "The only modification of the original requests should be the addition of x-datadog-sampling-priority tracing headers."
        )
        assertRequestsEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        assertRequestsEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenOnlyRUMInstrumentationEnabled_whenInterceptingRequests_itDoesNotModifyThem() throws {
        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(tracingInstrumentationEnabled: false, rumInstrumentationEnabled: true),
            handler: handler
        )
        Global.sharedTracer = Tracer.mockAny(in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        assertRequestsEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should not be modified.")
        assertRequestsEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        assertRequestsEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    func testGivenTracingInstrumentationEnabledButTracerNotRegistered_whenInterceptingRequests_itDoesNotInjectTracingContextToAnyRequest() throws {
        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(tracingInstrumentationEnabled: true, rumInstrumentationEnabled: .random()),
            handler: handler
        )
        XCTAssertTrue(Global.sharedTracer is DDNoopTracer)

        // When
        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // Then
        assertRequestsEqual(firstPartyRequest, interceptedFirstPartyRequest, "Intercepted 1st party request should not be modified.")
        assertRequestsEqual(thirdPartyRequest, interceptedThirdPartyRequest, "Intercepted 3rd party request should not be modified.")
        assertRequestsEqual(internalRequest, interceptedInternalRequest, "Intercepted internal request should not be modified.")
    }

    // MARK: - URLSessionTask Interception

    func testGivenTracingInstrumentationEnabled_whenInterceptingURLSessionTasks_itNotifiesStartAndCompletion() throws {
        let interceptionStartedExpectation = expectation(description: "Start task interception")
        interceptionStartedExpectation.expectedFulfillmentCount = 3
        handler.didNotifyInterceptionStart = { interception in
            XCTAssertFalse(interception.isDone)
            interceptionStartedExpectation.fulfill()
        }

        let interceptionCompletedExpectation = expectation(description: "Complete task interception")
        interceptionCompletedExpectation.expectedFulfillmentCount = 3
        handler.didNotifyInterceptionCompletion = { interception in
            XCTAssertTrue(interception.isDone)
            interceptionCompletedExpectation.fulfill()
        }

        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(tracingInstrumentationEnabled: true, rumInstrumentationEnabled: .random()),
            handler: handler
        )
        Global.sharedTracer = Tracer.mockAny(in: core)
        defer { Global.sharedTracer = DDNoopGlobals.tracer }
        let sessionWithCustomFirstPartyHosts = URLSession.mockWith(
            DDURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [alternativeFirstPartyRequest.url!.host!: [.datadog]])
        )

        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)
        let interceptedCustomFirstPartyRequest = interceptor.modify(
            request: alternativeFirstPartyRequest,
            session: sessionWithCustomFirstPartyHosts
        )

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: interceptedFirstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: interceptedThirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: interceptedInternalRequest, response: .mockAny())
        let alternativeFirstPartyTask: URLSessionTask = .mockWith(request: interceptedCustomFirstPartyRequest, response: .mockAny())

        let firstPartyTaskData: Data = .mockRandom()
        let thirdPartyTaskData: Data = .mockRandom()
        let internalTaskData: Data = .mockRandom()
        let alternativeFirstPartyTaskData: Data = .mockRandom()

        // swiftlint:disable opening_brace
        callConcurrently(
            { interceptor.taskCreated(task: firstPartyTask) },
            { interceptor.taskCreated(task: thirdPartyTask) },
            { interceptor.taskCreated(task: internalTask) },
            { interceptor.taskCreated(task: alternativeFirstPartyTask, session: sessionWithCustomFirstPartyHosts) }
        )
        callConcurrently(
            { interceptor.taskReceivedData(task: firstPartyTask, data: firstPartyTaskData) },
            { interceptor.taskReceivedData(task: thirdPartyTask, data: thirdPartyTaskData) },
            { interceptor.taskReceivedData(task: internalTask, data: internalTaskData) },
            { interceptor.taskReceivedData(task: alternativeFirstPartyTask, data: alternativeFirstPartyTaskData) }
        )
        callConcurrently(
            closures: [
                { interceptor.taskCompleted(task: firstPartyTask, error: nil) },
                { interceptor.taskCompleted(task: thirdPartyTask, error: nil) },
                { interceptor.taskCompleted(task: internalTask, error: nil) },
                { interceptor.taskCompleted(task: alternativeFirstPartyTask, error: nil) },
                { interceptor.taskMetricsCollected(task: firstPartyTask, metrics: .mockAny()) },
                { interceptor.taskMetricsCollected(task: thirdPartyTask, metrics: .mockAny()) },
                { interceptor.taskMetricsCollected(task: internalTask, metrics: .mockAny()) },
                { interceptor.taskMetricsCollected(task: alternativeFirstPartyTask, metrics: .mockAny()) }
            ],
            iterations: 1
        )
        // swiftlint:enable opening_brace

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        var interception: TaskInterception

        // We compare `URLRequests` by their `.url` in following assertions
        // due to https://openradar.appspot.com/radar?id=4988276943355904

        let startedInterceptions = handler.startedInterceptions
        XCTAssertEqual(startedInterceptions.count, 3)

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == firstPartyRequest.url }, "Interception should be started for 1st party request."
        )
        XCTAssertNotNil(interception.spanContext, "Span context should be set for 1st party request.")

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == thirdPartyRequest.url }, "Interception should be started for 3rd party request."
        )
        XCTAssertNil(interception.spanContext, "Span context should NOT be set for 3rd party request.")

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == alternativeFirstPartyRequest.url }, "Interception should be started for custom 1st party request."
        )
        XCTAssertNotNil(interception.spanContext, "Span context should be set for custom 1st party request.")

        let completedInterceptions = handler.completedInterceptions
        XCTAssertEqual(completedInterceptions.count, 3)

        interception = try XCTUnwrap(
            completedInterceptions.first { $0.request.url == firstPartyRequest.url }, "Interception should be completed for 1st party request."
        )
        XCTAssertNotNil(interception.spanContext, "Span context should be set for 1st party request.")
        XCTAssertEqual(interception.data, firstPartyTaskData, "Data should be recorded for 1st party request.")

        interception = try XCTUnwrap(
            completedInterceptions.first { $0.request.url == thirdPartyRequest.url }, "Interception should be completed for 3rd party request."
        )
        XCTAssertNil(interception.spanContext, "Span context should NOT be set for 3rd party request.")
        XCTAssertEqual(interception.data, thirdPartyTaskData, "Data should be recorded for 3rd party request.")

        interception = try XCTUnwrap(
            completedInterceptions.first { $0.request.url == alternativeFirstPartyRequest.url }, "Interception should be completed for custom 1st party request."
        )
        XCTAssertNotNil(interception.spanContext, "Span context should be set for custom 1st party request.")
        XCTAssertEqual(interception.data, alternativeFirstPartyTaskData, "Data should be recorded for custom 1st party request.")
    }

    func testGivenOnlyRUMInstrumentationEnabled_whenInterceptingURLSessionTasks_itNotifiesStartAndCompletion() throws {
        let interceptionStartedExpectation = expectation(description: "Start task interception")
        interceptionStartedExpectation.expectedFulfillmentCount = 2
        handler.didNotifyInterceptionStart = { interception in
            XCTAssertFalse(interception.isDone)
            interceptionStartedExpectation.fulfill()
        }

        let interceptionCompletedExpectation = expectation(description: "Complete task interception")
        interceptionCompletedExpectation.expectedFulfillmentCount = 2
        handler.didNotifyInterceptionCompletion = { interception in
            XCTAssertTrue(interception.isDone)
            interceptionCompletedExpectation.fulfill()
        }

        // Given
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(tracingInstrumentationEnabled: false, rumInstrumentationEnabled: true),
            handler: handler
        )

        let interceptedFirstPartyRequest = interceptor.modify(request: firstPartyRequest)
        let interceptedThirdPartyRequest = interceptor.modify(request: thirdPartyRequest)
        let interceptedInternalRequest = interceptor.modify(request: internalRequest)

        // When
        let firstPartyTask: URLSessionTask = .mockWith(request: interceptedFirstPartyRequest, response: .mockAny())
        let thirdPartyTask: URLSessionTask = .mockWith(request: interceptedThirdPartyRequest, response: .mockAny())
        let internalTask: URLSessionTask = .mockWith(request: interceptedInternalRequest, response: .mockAny())

        let firstPartyTaskData: Data = .mockRandom()
        let thirdPartyTaskData: Data = .mockRandom()
        let internalTaskData: Data = .mockRandom()

        // swiftlint:disable opening_brace
        callConcurrently(
            { interceptor.taskCreated(task: firstPartyTask) },
            { interceptor.taskCreated(task: thirdPartyTask) },
            { interceptor.taskCreated(task: internalTask) }
        )
        callConcurrently(
            { interceptor.taskReceivedData(task: firstPartyTask, data: firstPartyTaskData) },
            { interceptor.taskReceivedData(task: thirdPartyTask, data: thirdPartyTaskData) },
            { interceptor.taskReceivedData(task: internalTask, data: internalTaskData) }
        )
        callConcurrently(
            { interceptor.taskCompleted(task: firstPartyTask, error: nil) },
            { interceptor.taskCompleted(task: thirdPartyTask, error: nil) },
            { interceptor.taskCompleted(task: internalTask, error: nil) },
            { interceptor.taskMetricsCollected(task: firstPartyTask, metrics: .mockAny()) },
            { interceptor.taskMetricsCollected(task: thirdPartyTask, metrics: .mockAny()) },
            { interceptor.taskMetricsCollected(task: internalTask, metrics: .mockAny()) }
        )
        // swiftlint:enable opening_brace

        // Then
        waitForExpectations(timeout: 0.25, handler: nil)

        var interception: TaskInterception

        // We compare `URLRequests` by their `.url` in following assertions
        // due to https://openradar.appspot.com/radar?id=4988276943355904

        let startedInterceptions = handler.startedInterceptions
        XCTAssertEqual(startedInterceptions.count, 2)

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == firstPartyRequest.url }, "Interception should be started for 1st party request."
        )

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == thirdPartyRequest.url }, "Interception should be started for 3rd party request."
        )

        let completedInterceptions = handler.completedInterceptions
        XCTAssertEqual(completedInterceptions.count, 2)

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == firstPartyRequest.url }, "Interception should be completed for 1st party request."
        )
        XCTAssertEqual(interception.data, firstPartyTaskData)

        interception = try XCTUnwrap(
            startedInterceptions.first { $0.request.url == thirdPartyRequest.url }, "Interception should be completed for 3rd party request."
        )
        XCTAssertEqual(interception.data, thirdPartyTaskData)

        let allInterceptions = startedInterceptions + completedInterceptions
        allInterceptions.forEach { interception in
            XCTAssertNil(interception.spanContext, "Span context should NOT be set when Tracing instrumentation is disabled.")
        }
    }

    // MARK: - Thread Safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let interceptor = URLSessionInterceptor(
            configuration: mockConfiguration(tracingInstrumentationEnabled: true, rumInstrumentationEnabled: true),
            handler: handler
        )

        let requests = [firstPartyRequest, thirdPartyRequest, internalRequest]
        let tasks = (0..<10).map { _ in URLSessionTask.mockWith(request: .mockAny(), response: .mockAny()) }

        // swiftlint:disable opening_brace trailing_closure
        callConcurrently(
            closures: [
                { _ = interceptor.modify(request: requests.randomElement()!) },
                { interceptor.taskCreated(task: tasks.randomElement()!) },
                { interceptor.taskReceivedData(task: tasks.randomElement()!, data: .mockRandom()) },
                { interceptor.taskMetricsCollected(task: tasks.randomElement()!, metrics: .mockAny()) },
                { interceptor.taskCompleted(task: tasks.randomElement()!, error: nil) }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    // MARK: - Helpers

    /// Because of https://openradar.appspot.com/radar?id=4988276943355904
    /// it is not always reliable to compare `URLRequests` using in-build equality operator (`r1 == r2`).
    /// This method implements a workaround by comparing request HTTP headers before checking equality.
    private func assertRequestsEqual(
        _ request1: URLRequest,
        _ request2: URLRequest,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let headers1 = request1.allHTTPHeaderFields ?? [:]
        let headers2 = request2.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers1, headers2, message, file: file, line: line)
        XCTAssertEqual(request1, request2, message, file: file, line: line)
    }
}
