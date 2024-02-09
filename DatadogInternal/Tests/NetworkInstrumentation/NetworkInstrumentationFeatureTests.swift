/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class NetworkInstrumentationFeatureTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>!
    private var handler: URLSessionHandlerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        core = SingleFeatureCoreMock()
        handler = URLSessionHandlerMock()

        try core.register(urlSessionHandler: handler)
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    // MARK: - Interception Flow

    func testGivenURLSessionWithDatadogDelegate_whenUsingTaskWithURL_itNotifiesInterceptor() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.onInterceptionDidStart = { _ in
            notifyInterceptionDidStart.fulfill()
        }
        handler.onInterceptionDidComplete = { _ in
            notifyInterceptionDidComplete.fulfill()
        }

        // Given
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockAny())
        task.resume()

        // Then
        wait(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testGivenURLSessionWithDatadogDelegate_whenUsingTaskWithURLRequest_itNotifiesInterceptor() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given
        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        session
            .dataTask(with: URLRequest(url: url))
            .resume()

        // Then
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testGivenURLSessionWithCustomDelegate_whenUsingAsyncDataFromURL_itNotifiesInterceptor() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        _ = try await session.data(from: URL.mockAny(), delegate: delegate)

        // Then
        await dd_fulfillment(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        _ = server.waitAndReturnRequests(count: 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testGivenURLSessionWithCustomDelegate_whenUsingAsyncDataForURLRequest_itNotifiesInterceptor() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { interception in
            XCTAssertTrue(interception.isFirstPartyRequest)
            notifyInterceptionDidStart.fulfill()
        }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given
        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        _ = try await session.data(for: URLRequest(url: url), delegate: delegate)

        // Then
        await dd_fulfillment(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        _ = server.waitAndReturnRequests(count: 1)
    }

    // MARK: - Interception Values

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithFailure_itPassesAllValuesToTheInterceptor() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2

        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1: URL = .mockRandom()
        session
            .dataTask(with: url1)
            .resume()

        let url2: URL = .mockRandom()
        session
            .dataTask(with: URLRequest(url: url2)) { _,_,_ in }
            .resume()

        // Then
        _ = server.waitAndReturnRequests(count: 2)

        waitForExpectations(timeout: 5, handler: nil)
        let dateAfterAllRequests = Date()

        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        try [url1, url2].forEach { url in
            let interception = try XCTUnwrap(handler.interception(for: url))
            let metrics = try XCTUnwrap(interception.metrics)
            XCTAssertGreaterThan(metrics.fetch.start, dateBeforeAnyRequests)
            XCTAssertLessThan(metrics.fetch.end, dateAfterAllRequests)
            XCTAssertNil(interception.data, "Data should not be recorded for \(url)")
            XCTAssertEqual((interception.completion?.error as? NSError)?.localizedDescription, "some error")
        }
    }

    func testGivenURLSessionWithCustomDelegate_whenNotInstrumented_itDoesNotInterceptTasks() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: Data()))

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession() // no custom delegate

        // When
        let url1: URL = .mockRandom()
        session
            .dataTask(with: url1)
            .resume()

        let url2: URL = .mockRandom()
        session
            .dataTask(with: URLRequest(url: url2))
            .resume()

        // Then
        _ = server.waitAndReturnRequests(count: 2)
        XCTAssertEqual(handler.interceptions.count, 0, "Interceptor should not record tasks")
    }

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithSuccess_itPassesAllValuesToTheInterceptor() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2

        let randomData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: randomData))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1 = URL.mockRandom()
        session
            .dataTask(with: url1)
            .resume()

        let url2 = URL.mockRandom()
        session
            .dataTask(with: URLRequest(url: url2))
            .resume()

        // Then
        _ = server.waitAndReturnRequests(count: 2)

        waitForExpectations(timeout: 5, handler: nil)
        let dateAfterAllRequests = Date()
        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        try [url1, url2].forEach { url in
            let interception = try XCTUnwrap(handler.interception(for: url))
            let metrics = try XCTUnwrap(interception.metrics)
            XCTAssertGreaterThan(metrics.fetch.start, dateBeforeAnyRequests)
            XCTAssertLessThan(metrics.fetch.end, dateAfterAllRequests)
            XCTAssertEqual(interception.data, randomData)
            XCTAssertNotNil(interception.completion)
            XCTAssertNil(interception.completion?.error)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testGivenURLSessionWithCustomDelegate_whenUsingAsyncData_itPassesAllValuesToTheInterceptor() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2

        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(
            delivery: .failure(error: expectedError),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession()

        // When
        _ = try? await session.data(from: .mockRandom(), delegate: delegate) // intercepted
        _ = try? await session.data(for: URLRequest(url: .mockRandom()), delegate: delegate) // intercepted
        _ = try? await session.data(for: URLRequest(url: .mockRandom())) // not intercepted

        // Then
        await dd_fulfillment(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        _ = server.waitAndReturnRequests(count: 3)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        handler.interceptions.forEach { id, interception in
            XCTAssertGreaterThan(interception.metrics?.fetch.start ?? .distantPast, dateBeforeAnyRequests)
            XCTAssertLessThan(interception.metrics?.fetch.end ?? .distantFuture, dateAfterAllRequests)
            XCTAssertNil(interception.data, "Data should not be recorded for \(id)")
            XCTAssertEqual((interception.completion?.error as? NSError)?.localizedDescription, "some error")
        }
    }

    func testGivenURLSessionTask_withCustomDelegate_itInterceptsRequests() throws {
        // pre iOS 15 cannot set delegate per task
        guard #available(iOS 15, tvOS 15, *) else {
            return
        }

        let notifyInterceptionDidComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        // Given
        let delegate1 = MockDelegate()
        let delegate2 = MockDelegate2()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When
        let task1 = session.dataTask(with: URL.mockWith(url: "https://www.foo.com/1")) // intercepted
        task1.delegate = delegate1
        task1.resume()

        let task2 = session.dataTask(with: URL.mockWith(url: "https://www.foo.com/2")) // intercepted
        task2.delegate = delegate1
        task2.resume()

        let task3 = session.dataTask(with: URL.mockWith(url: "https://www.foo.com/3")) // not intercepted
        task3.delegate = delegate2
        task3.resume()

        // Then
        _ = server.waitAndReturnRequests(count: 3)
        waitForExpectations(timeout: 5, handler: nil)
        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should intercept 2 tasks")
    }

    // MARK: - Usage

    @available(*, deprecated)
    func testItCanBeInitializedBeforeInitializingDefaultSDKCore() throws {
        // Given
        let delegate1 = DatadogURLSessionDelegate()
        let delegate2 = DatadogURLSessionDelegate(additionalFirstPartyHosts: [])
        let delegate3 = DatadogURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [:])

        // When
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        // Then
        XCTAssertNotNil(delegate1.interceptor)
        XCTAssertNotNil(delegate2.interceptor)
        XCTAssertNotNil(delegate3.interceptor)
    }

    @available(*, deprecated)
    func testItCanBeInitializedAfterInitializingDefaultSDKCore() throws {
        // Given
        CoreRegistry.register(default: core)
        defer { CoreRegistry.unregisterDefault() }

        // When
        let delegate1 = DatadogURLSessionDelegate()
        let delegate2 = DatadogURLSessionDelegate(additionalFirstPartyHosts: [])
        let delegate3 = DatadogURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [:])

        // Then
        XCTAssertNotNil(delegate1.interceptor)
        XCTAssertNotNil(delegate2.interceptor)
        XCTAssertNotNil(delegate3.interceptor)
    }

    @available(*, deprecated)
    func testItOnlyKeepsInstrumentationWhileSDKCoreIsAvailableInMemory() throws {
        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        // Then
        XCTAssertNotNil(delegate.interceptor)

        // When (deinitialize core)
        core = nil
        // Then
        XCTAssertNil(delegate.interceptor)
    }

    func testWhenEnableInstrumentationOnTheSameDelegate_thenItPrintsAWarning() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        URLSessionInstrumentation.enable(with: .init(delegateClass: MockDelegate.self), in: core)
        URLSessionInstrumentation.enable(with: .init(delegateClass: MockDelegate.self), in: core)

        // Then
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            The delegate class MockDelegate is already instrumented.
            The previous instrumentation will be disabled in favor of the new one.
            """
        )
    }

    // MARK: - URLRequest Interception

    func testGivenOpenTracing_whenInterceptingRequests_itInjectsTrace() throws {
        // Given
        var request: URLRequest = .mockWith(url: "https://test.com")
        let writer = HTTPHeadersWriter(sampler: .mockKeepAll())
        handler.firstPartyHosts = .init(["test.com": [.datadog]])
        handler.parentSpan = TraceContext(traceID: .mock(1), spanID: .mock(2))

        // When
        writer.write(traceID: .mock(1), spanID: .mock(3))
        request.allHTTPHeaderFields = writer.traceHeaderFields

        let task: URLSessionTask = .mockWith(request: request, response: .mockAny())
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.intercept(task: task, additionalFirstPartyHosts: nil)
        feature.flush()

        // Then
        let interception = handler.interceptions.first?.value
        XCTAssertEqual(interception?.trace?.traceID, .mock(1))
        XCTAssertEqual(interception?.trace?.parentSpanID, .mock(2))
        XCTAssertEqual(interception?.trace?.spanID, .mock(3))
    }

    func testGivenOpenTelemetry_b3single_whenInterceptingRequests_itInjectsTrace() throws {
        // Given
        var request: URLRequest = .mockWith(url: "https://test.com")
        let writer = B3HTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .single)
        handler.firstPartyHosts = .init(["test.com": [.b3]])

        // When
        writer.write(traceID: .mock(1), spanID: .mock(3), parentSpanID: .mock(2))
        request.allHTTPHeaderFields = writer.traceHeaderFields

        let task: URLSessionTask = .mockWith(request: request, response: .mockAny())
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.intercept(task: task, additionalFirstPartyHosts: nil)
        feature.flush()

        // Then
        let interception = handler.interceptions.first?.value
        XCTAssertEqual(interception?.trace?.traceID, .mock(1))
        XCTAssertEqual(interception?.trace?.parentSpanID, .mock(2))
        XCTAssertEqual(interception?.trace?.spanID, .mock(3))
    }

    func testGivenOpenTelemetry_b3multi_whenInterceptingRequests_itInjectsTrace() throws {
        // Given
        var request: URLRequest = .mockWith(url: "https://test.com")
        let writer = B3HTTPHeadersWriter(sampler: .mockKeepAll(), injectEncoding: .multiple)
        handler.firstPartyHosts = .init(["test.com": [.b3multi]])

        // When
        writer.write(traceID: .mock(1), spanID: .mock(3), parentSpanID: .mock(2))
        request.allHTTPHeaderFields = writer.traceHeaderFields

        let task: URLSessionTask = .mockWith(request: request, response: .mockAny())
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.intercept(task: task, additionalFirstPartyHosts: nil)
        feature.flush()

        // Then
        let interception = handler.interceptions.first?.value
        XCTAssertEqual(interception?.trace?.traceID, .mock(1))
        XCTAssertEqual(interception?.trace?.parentSpanID, .mock(2))
        XCTAssertEqual(interception?.trace?.spanID, .mock(3))
    }

    func testGivenW3C_whenInterceptingRequests_itInjectsTrace() throws {
        // Given
        var request: URLRequest = .mockWith(url: "https://test.com")
        let writer = W3CHTTPHeadersWriter(
            sampler: .mockKeepAll(),
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ]
        )
        handler.firstPartyHosts = .init(["test.com": [.tracecontext]])
        handler.parentSpan = TraceContext(traceID: .mock(1), spanID: .mock(2))

        // When
        writer.write(traceID: .mock(1), spanID: .mock(3))
        request.allHTTPHeaderFields = writer.traceHeaderFields

        let task: URLSessionTask = .mockWith(request: request, response: .mockAny())
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.intercept(task: task, additionalFirstPartyHosts: nil)
        feature.flush()

        // Then
        let interception = handler.interceptions.first?.value
        XCTAssertEqual(interception?.trace?.traceID, .mock(1))
        XCTAssertEqual(interception?.trace?.parentSpanID, .mock(2))
        XCTAssertEqual(interception?.trace?.spanID, .mock(3))
    }

    // MARK: - First Party Hosts

    func testGivenHandler_whenInterceptingRequests_itDetectFirstPartyHost() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        // Given
        let delegate = MockDelegate()
        let firstPartyHosts: URLSessionInstrumentation.FirstPartyHostsTracing = .traceWithHeaders(hostsWithHeaders: ["test.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self, firstPartyHostsTracing: firstPartyHosts), in: core)

        let session = server.getInterceptedURLSession(delegate: delegate)
        let request: URLRequest = .mockWith(url: "https://test.com")

        handler.onInterceptionDidStart = {
            // Then
            XCTAssertTrue($0.isFirstPartyRequest)
            notifyInterceptionDidStart.fulfill()
        }

        // When
        session
            .dataTask(with: request)
            .resume()

        // Then
        waitForExpectations(timeout: 5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)
    }

    @available(*, deprecated)
    func testGivenDelegateSubclass_whenInterceptingRequests_itDetectFirstPartyHost() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        // Given

        let delegate = DatadogURLSessionDelegate(
            in: core,
            additionalFirstPartyHostsWithHeaderTypes: ["test.com": [.datadog]]
        )

        let session = server.getInterceptedURLSession(delegate: delegate)
        let request: URLRequest = .mockWith(url: "https://test.com")

        handler.onInterceptionDidStart = {
            // Then
            XCTAssertTrue($0.isFirstPartyRequest)
            notifyInterceptionDidStart.fulfill()
        }

        // When
        session
            .dataTask(with: request)
            .resume()

        session
            .dataTask(with: request) { _,_,_ in }
            .resume()

        // Then
        waitForExpectations(timeout: 5, handler: nil)
        _ = server.waitAndReturnRequests(count: 2)

        // release the delegate to unswizzle
        session.finishTasksAndInvalidate()
    }

    @available(*, deprecated)
    func testGivenCompositeDelegate_whenInterceptingRequests_itDetectFirstPartyHost() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        // Given
        class CompositeDelegate: NSObject, URLSessionDataDelegate, __URLSessionDelegateProviding {
            let ddURLSessionDelegate: DatadogURLSessionDelegate

            required init(in core: DatadogCoreProtocol) {
                ddURLSessionDelegate = DatadogURLSessionDelegate(
                    in: core,
                    additionalFirstPartyHostsWithHeaderTypes: ["test.com": [.datadog, .tracecontext]]
                )

                super.init()
            }
        }

        let delegate = CompositeDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)
        let request: URLRequest = .mockWith(url: "https://test.com")

        handler.onInterceptionDidStart = {
            // Then
            XCTAssertTrue($0.isFirstPartyRequest)
            notifyInterceptionDidStart.fulfill()
        }

        // When
        session
            .dataTask(with: request)
            .resume()

        session
            .dataTask(with: request) { _,_,_ in }
            .resume()

        // Then
        waitForExpectations(timeout: 5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        // release the delegate to unswizzle
        session.finishTasksAndInvalidate()
    }

    // MARK: - Thread Safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        let requests = [
            URLRequest(url: URL(string: "https://api.first-party.com/v1/endpoint")!),
            URLRequest(url: URL(string: "https://api.third-party.com/v1/endpoint")!),
            URLRequest(url: URL(string: "https://dd.internal.com/v1/endpoint")!)
        ]
        let tasks = (0..<10).map { _ in URLSessionTask.mockWith(request: .mockAny(), response: .mockAny()) }

        // swiftlint:disable opening_brace trailing_closure
        callConcurrently(
            closures: [
                { feature.handlers = [self.handler] },
                { _ = feature.intercept(request: requests.randomElement()!, additionalFirstPartyHosts: nil) },
                { feature.intercept(task: tasks.randomElement()!, additionalFirstPartyHosts: nil) },
                { feature.task(tasks.randomElement()!, didReceive: .mockRandom()) },
                { feature.task(tasks.randomElement()!, didFinishCollecting: .mockAny()) },
                { feature.task(tasks.randomElement()!, didCompleteWithError: nil) },
                { try? feature.bind(configuration: .init(delegateClass: MockDelegate.self)) },
                { feature.unbind(delegateClass: MockDelegate.self) }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    class MockDelegate: NSObject, URLSessionDataDelegate {
    }

    class MockDelegate2: NSObject, URLSessionDataDelegate {
    }
}
