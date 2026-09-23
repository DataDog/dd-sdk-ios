/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
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
        // Flush the feature's serial queue before releasing the core to ensure
        // all pending async blocks (especially from the concurrent test) complete
        // before the feature is deallocated. Without this, a block executing past
        // `guard let self = self` holds the feature alive, causing deallocation
        // on a background thread — which can race with the next test's swizzles
        // via `_unswizzle`'s transient IMP resets.
        core?.get(feature: NetworkInstrumentationFeature.self)?.flush()
        core = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    /// Sets up a test with interception expectations.
    /// Returns server, start expectation, and complete expectation.
    private func setupInterceptionTest(
        dataSize: Int = 10,
        error: NSError? = nil,
        skipIsMainThreadCheck: Bool = false,
        expectedFulfillmentCount: Int = 1
    ) -> (ServerMock, XCTestExpectation, XCTestExpectation) {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        notifyInterceptionDidStart.expectedFulfillmentCount = expectedFulfillmentCount
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = expectedFulfillmentCount

        let delivery: ServerMock.Delivery = error.map { .failure(error: $0) } ?? .success(response: .mockWith(statusCode: 200, mimeType: "application/json"), data: .mock(ofSize: dataSize))
        let server = ServerMock(delivery: delivery, skipIsMainThreadCheck: true)

        scopeHandler(to: server)
        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        return (server, notifyInterceptionDidStart, notifyInterceptionDidComplete)
    }

    /// Scopes `handler` to traffic produced by `server`'s URLSession. The resume swizzle is
    /// process-global, so foreign URLSession activity in the test process would otherwise reach
    /// the handler.
    private func scopeHandler(to server: ServerMock) {
        // When Swift access a member of a value stored as a weak reference (like `server?.isMyRequest(req)`
        // below), that call is wrapped by a scope that does the equivalent of temporarily holding it by a
        // strong reference, effectively extending its lifetime.
        //
        // The purpose of such mechanism is to prevent the situation where, if this code is running on a
        // specific thread, and code running on a different thread drops the last strong reference to the
        // object, the object does not get deallocated while being accessed by the original thread.
        //
        // When that happens, the object will be held only by the temporary reference, and as soon as the
        // call is over, its reference count will be decreased and the object will be released on the
        // specific thread that was temporarily holding it.
        //
        // This happens occasionally in these tests, causing a precondition failure and therefore a crash.
        // To avoid this, the server mocks need to be created with `skipIsMainThreadCheck` set to true to
        // bypass this check.
        XCTAssert(server.skipIsMainThreadCheck, "ServerMocks passed to this method must be created with skipIsMainThreadCheck set to `true`.")
        handler.shouldInterceptRequest = { [weak server] req in server?.isMyRequest(req) ?? false }
    }

    // MARK: - Registered Delegate Mode

    func testRegisteredDelegate_capturesMetricsForDataTaskWithURL() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given
        // Automatic mode (required)
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using data task with URL
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Registered delegate mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForDataTaskWithURLRequest() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let server = ServerMock(delivery: .success(response: .mockWith(statusCode: 200, mimeType: "application/json"), data: .mock(ofSize: 10)), skipIsMainThreadCheck: true)

        handler.onRequestMutation = { _, _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }
        scopeHandler(to: server)

        // Given
        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using data task with URLRequest
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Registered delegate mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForUploadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using upload task
        let task = session.uploadTask(with: URLRequest(url: URL.mockAny()), from: Data.mockRandom(ofSize: 20))
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Registered delegate mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForDownloadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using download task
        let task = session.downloadTask(with: URL.mockAny())
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Download task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data not captured for download tasks (saved to file)")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncDataFromURL() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using async data API with delegate
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncDataWithSessionDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using async data API without delegate
        _ = try await session.data(from: URL.mockAny())

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncDataWithPerTaskDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session without delegate
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - using async data API with delegate
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncUploadWithPerTaskDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session without delegate
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - using async upload API with delegate
        _ = try await session.upload(for: URLRequest(url: URL.mockAny()), from: Data.mockRandom(ofSize: 20), delegate: delegate)

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data is not captured when using Async API")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncUploadWithSessionDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using async upload API
        _ = try await session.upload(for: URLRequest(url: URL.mockAny()), from: Data.mockRandom(ofSize: 20))

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testRegisteredDelegate_capturesMetricsForAsyncDataTaskWithURLRequest() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { interception in
            XCTAssertTrue(interception.isFirstPartyRequest)
            notifyInterceptionDidStart.fulfill()
        }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }
        scopeHandler(to: server)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )

        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using async data API with delegate
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForCombineDataTask() throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When using data task publisher
        let cancellable = session.dataTaskPublisher(for: URL.mockAny())
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )

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
        _ = cancellable // extend lifetime of Combine subscription

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Registered delegate mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForCompletionHandlerDataTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using completion handler data task
        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in }
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Registered delegate mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_capturesMetricsForCompletionHandlerUploadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Registered delegate mode
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Session with delegate
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When - using completion handler upload task
        let task = session.uploadTask(
            with: URLRequest(url: URL.mockAny()),
            from: Data.mockRandom(ofSize: 20)
        ) { _, _, _ in }
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with session using registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Upload tasks with completion handler don't capture data via delegate")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testRegisteredDelegate_doesNotBufferMediaResponseBody() throws {
        // Regression test for RUM-16927.
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let server = ServerMock(
            delivery: .success(
                response: .mockWith(statusCode: 200, mimeType: "image/jpeg"),
                data: .mockRandom(ofSize: 1_024) // well under the 512 KB cap
            ),
            skipIsMainThreadCheck: true
        )
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }
        scopeHandler(to: server)

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        session.dataTask(with: URL.mockAny()).resume()

        wait(for: [notifyInterceptionDidComplete], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertNil(interception.data, "Media response body must not be buffered")
    }

    func testRegisteredDelegate_truncatesBodyAtSizeCap() throws {
        // Regression test for RUM-16927.
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let overCapSize = NetworkInstrumentationFeature.maxBufferedBodySize + 1_024
        let server = ServerMock(
            delivery: .success(
                response: .mockWith(statusCode: 200, mimeType: "application/json"),
                data: .mockRandom(ofSize: overCapSize)
            ),
            skipIsMainThreadCheck: true
        )
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }
        scopeHandler(to: server)

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        session.dataTask(with: URL.mockAny()).resume()

        wait(for: [notifyInterceptionDidComplete], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertNil(interception.data)
    }

    // MARK: - Automatic Mode

    func testAutomaticMode_tracksTasksWithoutDelegateRegistration() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Automatic mode (no delegate class)
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Session without delegate
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - using data task completion handler
        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in }
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Data should be captured by completion handler")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_whenTaskIsResumedTwice_itMutatesAndStartsItOnlyOnce() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)
        let requestMutation = expectation(description: "Mutate request once")
        requestMutation.assertForOverFulfill = true
        let url = try XCTUnwrap(URL(string: "https://example.com/repeated-resume-\(UUID().uuidString)"))
        handler.onRequestMutation = { request, _, _ in
            if request.url == url {
                requestMutation.fulfill()
            }
        }

        let task = session.dataTask(with: url)
        task.resume()
        task.resume()

        wait(
            for: [requestMutation, notifyInterceptionDidStart, notifyInterceptionDidComplete],
            timeout: 5,
            enforceOrder: false
        )
        _ = server.waitAndReturnRequests(count: 1)

        XCTAssertEqual(handler.interceptions.count, 1)
    }

    func testAutomaticMode_whenTaskSuspendsAndResumes_itKeepsOnePreparedLifecycle() throws {
        let url = URL(string: "https://192.0.2.0:9999/suspend-resume")!
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["192.0.2.0": [.datadog]])
        handler.shouldInterceptRequest = { $0.url == url }
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.onRequestMutation = { [weak handler = handler] request, _, _ in
            guard request.url == url else {
                return
            }
            mutations.mutate { $0 += 1 }
            var prepared = request
            prepared.setValue("retained", forHTTPHeaderField: "X-Preparation")
            handler?.modifiedRequest = prepared
        }
        let started = expectation(description: "One start across suspend/resume")
        let completed = expectation(description: "One completion across suspend/resume")
        let appCompleted = expectation(description: "Native cancellation completes")
        handler.onInterceptionDidStart = { _ in started.fulfill() }
        handler.onInterceptionDidComplete = { _ in completed.fulfill() }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // TEST-NET-1 keeps a real task in flight until the explicit cancellation.
        let task = session.dataTask(with: url) { _, _, error in
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorCancelled)
            appCompleted.fulfill()
        }

        let firstRunning = expectation(for: NSPredicate { object, _ in
            (object as? URLSessionTask)?.state == .running
        }, evaluatedWith: task)
        task.resume()
        wait(for: [firstRunning], timeout: 5)
        XCTAssertEqual(task.state, .running)
        let suspended = expectation(for: NSPredicate { object, _ in
            (object as? URLSessionTask)?.state == .suspended
        }, evaluatedWith: task)
        task.suspend()
        wait(for: [suspended], timeout: 5)
        XCTAssertEqual(task.state, .suspended)
        let secondRunning = expectation(for: NSPredicate { object, _ in
            (object as? URLSessionTask)?.state == .running
        }, evaluatedWith: task)
        task.resume()
        wait(for: [secondRunning], timeout: 5)
        XCTAssertEqual(task.state, .running)
        task.cancel()
        wait(for: [started, completed, appCompleted], timeout: 5)
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()

        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertEqual(task.currentRequest?.value(forHTTPHeaderField: "X-Preparation"), "retained")
        XCTAssertNotNil(handler.interceptions.first?.value.completion)
    }

    func testAutomaticMode_whenResumeIsConcurrent_itPreparesBeforeForwardingEitherCall() throws {
        let (server, started, completed) = setupInterceptionTest()
        let url = try XCTUnwrap(URL(string: "https://example.com/concurrent-resume"))
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let mutations = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { task, resume in
            if task.currentRequest?.url == url {
                forwarded.mutate { $0 += 1 }
            }
            resume()
        }
        defer { previous.unswizzle() }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession()
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        let mutationEntered = expectation(description: "First mutation entered")
        let firstResumeReturned = expectation(description: "First resume returned")
        let releaseMutation = DispatchSemaphore(value: 0)
        defer { releaseMutation.signal() }
        handler.onRequestMutation = { [weak handler = handler] request, _, _ in
            guard request.url == url else {
                return
            }
            var first = false
            mutations.mutate { $0 += 1; first = $0 == 1 }
            guard first else {
                return
            }
            var modified = request
            modified.setValue("prepared-once", forHTTPHeaderField: "X-Preparation")
            handler?.modifiedRequest = modified
            mutationEntered.fulfill()
            XCTAssertEqual(releaseMutation.wait(timeout: .now() + 5), .success)
        }

        DispatchQueue.global().async {
            task.resume()
            firstResumeReturned.fulfill()
        }
        wait(for: [mutationEntered], timeout: 5)
        task.resume()
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(forwarded.wrappedValue, 0, "Neither native resume may outrun header preparation")
        XCTAssertEqual(task.state, .suspended)
        releaseMutation.signal()
        wait(for: [firstResumeReturned, started, completed], timeout: 5)
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()

        let requests = server.waitAndReturnRequests(count: 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-Preparation"), "prepared-once")
        XCTAssertEqual(forwarded.wrappedValue, 2, "Both previous implementations must eventually run")
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertNotNil(handler.interceptions.first?.value.completion)
    }

    func testAutomaticMode_whenDifferentTasksPrepareInParallel_itKeepsIndependentLifecycles() throws {
        try assertDifferentTasksPrepareInParallel(mode: .automatic)
    }

    func testRegisteredDelegate_whenDifferentTasksPrepareInParallel_itKeepsIndependentLifecycles() throws {
        try assertDifferentTasksPrepareInParallel(mode: .registeredDelegate)
    }

    /// Keeps every task inside request mutation before releasing either half of the tasks.
    /// Native transport is withheld so callbacks can be injected with distinct per-task payloads.
    private func assertDifferentTasksPrepareInParallel(mode: TrackingMode) throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let taskCount = 16
        let sessions = (0..<2).map { _ in
            URLSession(configuration: .ephemeral, delegate: mode == .registeredDelegate ? SessionDataDelegateMock() : nil, delegateQueue: nil)
        }
        defer { sessions.forEach { $0.invalidateAndCancel() } }
        let urls = (0..<taskCount).map { URL(string: "https://example.com/parallel-preparation/\($0)")! }
        let tasks = urls.enumerated().map { index, url in
            var request = URLRequest(url: url)
            request.setValue(String(index), forHTTPHeaderField: "X-Task")
            return sessions[index % sessions.count].dataTask(with: request)
        }
        let indices = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ($0.element, $0.offset) })
        let releaseMutations = tasks.map { _ in DispatchSemaphore(value: 0) }
        defer {
            releaseMutations.forEach { $0.signal() }
            handler.onRequestMutation = nil
        }
        let mutations = ReadWriteLock(wrappedValue: [URL: Int]())
        let finishedMutations = ReadWriteLock(wrappedValue: Set<URL>())
        let forwarded = ReadWriteLock(wrappedValue: [URL: Int]())
        let order = ReadWriteLock(wrappedValue: [URL: [String]]())
        let entered = expectation(description: "Every distinct task enters preparation concurrently")
        entered.expectedFulfillmentCount = taskCount
        let firstHalfReturned = expectation(description: "Half the tasks finish while the others remain preparing")
        firstHalfReturned.expectedFulfillmentCount = taskCount / 2
        let allReturned = expectation(description: "All initial resume calls return")
        allReturned.expectedFulfillmentCount = taskCount

        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { candidate, continuation in
            guard let url = candidate.currentRequest?.url, let index = indices[url], candidate === tasks[index] else {
                continuation()
                return
            }
            XCTAssertTrue(finishedMutations.wrappedValue.contains(url), "Forwarding must follow this task's preparation")
            XCTAssertEqual(candidate.currentRequest?.value(forHTTPHeaderField: "X-Task"), String(index))
            var isFirstForward = false
            forwarded.mutate {
                $0[url, default: 0] += 1
                isFirstForward = $0[url] == 1
            }
            if isFirstForward && !index.isMultiple(of: 2) {
                feature.task(candidate, didCompleteWithError: nil)
            }
        }
        defer { previous.unswizzle() }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.shouldInterceptRequest = { $0.url.map { indices[$0] != nil } ?? false }
        handler.onInterceptionDidStart = { interception in
            order.mutate { $0[interception.request.url!, default: []].append("start") }
        }
        handler.onInterceptionDidComplete = { interception in
            order.mutate { $0[interception.request.url!, default: []].append("complete") }
        }
        handler.onRequestMutation = { request, _, _ in
            guard let url = request.url, let index = indices[url] else {
                return
            }
            mutations.mutate { $0[url, default: 0] += 1 }
            feature.task(tasks[index], didReceive: Data([UInt8(index)]))
            feature.task(tasks[index], didFinishCollecting: .mockWith())
            if index.isMultiple(of: 2) {
                feature.task(tasks[index], didCompleteWithError: nil)
            }
            entered.fulfill()
            XCTAssertEqual(releaseMutations[index].wait(timeout: .now() + 10), .success)
            finishedMutations.mutate { $0.insert(url) }
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        if mode == .registeredDelegate {
            try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        }

        for (index, task) in tasks.enumerated() {
            DispatchQueue.global().async {
                task.resume()
                if index < taskCount / 2 { firstHalfReturned.fulfill() }
                allReturned.fulfill()
            }
        }
        wait(for: [entered], timeout: 5)
        tasks.forEach { $0.resume() }
        feature.flush()
        XCTAssertTrue(forwarded.wrappedValue.isEmpty)
        XCTAssertTrue(order.wrappedValue.isEmpty)

        releaseMutations.prefix(taskCount / 2).forEach { $0.signal() }
        wait(for: [firstHalfReturned], timeout: 5)
        feature.flush()
        for index in urls.indices {
            XCTAssertEqual(forwarded.wrappedValue[urls[index], default: 0], index < taskCount / 2 ? 2 : 0)
            XCTAssertEqual(order.wrappedValue[urls[index], default: []], index < taskCount / 2 ? ["start", "complete"] : [])
        }

        releaseMutations.suffix(taskCount / 2).forEach { $0.signal() }
        wait(for: [allReturned], timeout: 5)
        feature.flush()
        XCTAssertEqual(handler.interceptions.count, taskCount)
        for (index, url) in urls.enumerated() {
            XCTAssertEqual(mutations.wrappedValue[url], 1)
            XCTAssertEqual(forwarded.wrappedValue[url], 2)
            XCTAssertEqual(order.wrappedValue[url], ["start", "complete"])
            let interception = try XCTUnwrap(handler.interception(for: url))
            XCTAssertEqual(interception.trackingMode, mode)
            XCTAssertEqual(interception.data, Data([UInt8(index)]))
            XCTAssertNotNil(interception.metrics)
            XCTAssertNotNil(interception.completion)
            XCTAssertNil(try Self.preparation(for: tasks[index], in: feature))
        }
    }

    func testAutomaticMode_whenConcurrentResumesReturn_itPreservesSubsequentSuspend() throws {
        #if os(watchOS)
        throw XCTSkip("watchOS ignores URLProtocol stubs; this test must keep native transport pending.")
        #else
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = URL(string: "https://example.com/suspend-after-concurrent-resumes")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingRequestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let completed = expectation(description: "Native cancellation completes")
        let task = session.dataTask(with: url) { _, _, error in
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorCancelled)
            completed.fulfill()
        }
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { candidate, resume in
            resume()
            if candidate === task { forwarded.mutate { $0 += 1 } }
        }
        defer { previous.unswizzle() }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.shouldInterceptRequest = { $0.url == url }
        let mutations = ReadWriteLock(wrappedValue: 0)
        let mutationEntered = expectation(description: "First preparation entered")
        let firstResumeReturned = expectation(description: "First resume and all deferred forwarding returned")
        let releaseMutation = DispatchSemaphore(value: 0)
        defer {
            releaseMutation.signal()
            handler.onRequestMutation = nil
        }
        handler.onRequestMutation = { request, _, _ in
            guard request.url == url else {
                return
            }
            mutations.mutate { $0 += 1 }
            mutationEntered.fulfill()
            XCTAssertEqual(releaseMutation.wait(timeout: .now() + 5), .success)
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        DispatchQueue.global().async {
            task.resume()
            firstResumeReturned.fulfill()
        }
        wait(for: [mutationEntered], timeout: 5)
        task.resume()
        XCTAssertEqual(forwarded.wrappedValue, 0)
        releaseMutation.signal()
        wait(for: [firstResumeReturned], timeout: 5)
        XCTAssertEqual(forwarded.wrappedValue, 2)

        // Order suspend after both public resume calls have returned. Suspending while the
        // first call is still forwarding would race with that call's remaining native work.
        task.suspend()
        feature.flush()
        XCTAssertEqual(task.state, .suspended)
        XCTAssertEqual(forwarded.wrappedValue, 2, "No resume may remain deferred after both calls return")

        task.resume()
        XCTAssertEqual(task.state, .running)
        XCTAssertEqual(forwarded.wrappedValue, 3)
        XCTAssertEqual(mutations.wrappedValue, 1)
        task.cancel()
        wait(for: [completed], timeout: 5)
        feature.flush()
        #endif
    }

    private final class PendingRequestURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { }
        override func stopLoading() { }
    }

    func testAutomaticMode_whenMutationResumesTheTask_itDoesNotReenterPreparation() throws {
        let (server, started, completed) = setupInterceptionTest()
        let url = try XCTUnwrap(URL(string: "https://example.com/reentrant-resume"))
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let mutations = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { task, resume in
            if task.currentRequest?.url == url {
                forwarded.mutate { $0 += 1 }
            }
            resume()
        }
        defer { previous.unswizzle() }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession()
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        handler.onRequestMutation = { [weak handler = handler] request, _, _ in
            guard request.url == url else {
                return
            }
            var first = false
            mutations.mutate { $0 += 1; first = $0 == 1 }
            guard first else {
                return
            }
            var modified = request
            modified.setValue("prepared-before-reentry", forHTTPHeaderField: "X-Preparation")
            handler?.modifiedRequest = modified
            task.resume()
            XCTAssertEqual(forwarded.wrappedValue, 0)
            XCTAssertEqual(task.state, .suspended)
        }

        task.resume()
        wait(for: [started, completed], timeout: 5, enforceOrder: true)
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()
        let requests = server.waitAndReturnRequests(count: 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-Preparation"), "prepared-before-reentry")
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(forwarded.wrappedValue, 2)
        XCTAssertEqual(handler.interceptions.count, 1)
        handler.onRequestMutation = nil
    }

    func testAutomaticMode_whenCancelledDuringMutation_itKeepsEarlyCompletion() throws {
        let (server, started, completed) = setupInterceptionTest()
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = try XCTUnwrap(URL(string: "https://example.com/cancel-during-preparation"))
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession()
        defer { session.finishTasksAndInvalidate() }
        let appCompleted = expectation(description: "Native cancellation completes before preparation")
        let task = session.dataTask(with: url) { _, _, error in
            XCTAssertEqual((error as NSError?)?.code, NSURLErrorCancelled)
            appCompleted.fulfill()
        }
        let mutationEntered = expectation(description: "Mutation entered")
        let resumeReturned = expectation(description: "Resume returned")
        let releaseMutation = DispatchSemaphore(value: 0)
        defer { releaseMutation.signal() }
        handler.onRequestMutation = { request, _, _ in
            guard request.url == url else {
                return
            }
            mutationEntered.fulfill()
            XCTAssertEqual(releaseMutation.wait(timeout: .now() + 5), .success)
        }

        DispatchQueue.global().async {
            task.resume()
            resumeReturned.fulfill()
        }
        wait(for: [mutationEntered], timeout: 5)
        task.cancel()
        wait(for: [appCompleted], timeout: 5)
        feature.flush()
        XCTAssertTrue(handler.interceptions.isEmpty, "Start cannot escape incomplete request preparation")
        releaseMutation.signal()
        wait(for: [started, completed, resumeReturned], timeout: 5)
        feature.flush()
        server.waitFor(requestsCompletion: 0, timeout: 0.05)

        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertEqual((interception.completion?.error as NSError?)?.code, NSURLErrorCancelled)
        XCTAssertNotNil(interception.startDate)
        XCTAssertNotNil(interception.endDate)
    }

    func testAutomaticMode_whenCompletedTaskResumes_itDoesNotInstrumentAgain() throws {
        let (server, started, completed) = setupInterceptionTest()
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = try XCTUnwrap(URL(string: "https://example.com/completed-resume"))
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.onRequestMutation = { request, _, _ in
            if request.url == url { mutations.mutate { $0 += 1 } }
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession()
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        task.resume()
        wait(for: [started, completed], timeout: 5, enforceOrder: true)
        feature.flush()
        _ = server.waitAndReturnRequests(count: 1)

        task.resume()
        feature.flush()
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertNotNil(handler.interceptions.first?.value.completion)
    }

    func testRegisteredDelegate_whenResumedTwice_itMutatesOnceAndPreservesMetrics() throws {
        let (server, started, completed) = setupInterceptionTest()
        let url = try XCTUnwrap(URL(string: "https://example.com/registered-repeated-resume"))
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.onRequestMutation = { request, _, _ in
            if request.url == url { mutations.mutate { $0 += 1 } }
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: SessionDataDelegateMock())
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)

        task.resume()
        task.resume()
        wait(for: [started, completed], timeout: 5, enforceOrder: true)
        core.get(feature: NetworkInstrumentationFeature.self)?.flush()
        _ = server.waitAndReturnRequests(count: 1)

        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertEqual(interception.trackingMode, .registeredDelegate)
        XCTAssertNotNil(interception.metrics)
        XCTAssertNotNil(interception.completion)
    }

    func testPreparation_automaticBodyAboveLimitIsPreserved() throws {
        let data = Data(repeating: 1, count: NetworkInstrumentationFeature.maxBufferedBodySize + 1)
        try assertPreparationCallbacks(mode: .automatic, chunks: [data], laterData: Data([2]), expectedData: data + Data([2]))
    }

    func testPreparation_registeredBodyAboveLimitDiscardsAllChunks() throws {
        let first = Data(repeating: 1, count: NetworkInstrumentationFeature.maxBufferedBodySize / 2)
        let second = Data(repeating: 2, count: NetworkInstrumentationFeature.maxBufferedBodySize / 2 + 1)
        try assertPreparationCallbacks(mode: .registeredDelegate, chunks: [first, second, Data([3])], laterData: Data([4]), expectedData: nil)
    }

    func testPreparation_registeredBodyAtLimitIsPreserved() throws {
        let data = Data(repeating: 1, count: NetworkInstrumentationFeature.maxBufferedBodySize)
        try assertPreparationCallbacks(mode: .registeredDelegate, chunks: [data], laterData: nil, expectedData: data)
    }

    func testPreparation_earlyCompletionFollowsBufferedDataAndMetrics() throws {
        try assertPreparationCallbacks(mode: .registeredDelegate, chunks: [Data([1, 2])], laterData: nil, expectedData: Data([1, 2]), completeDuringPreparation: true)
    }

    /// Injects callbacks through existing internal entry points while request mutation is active.
    /// A preceding task-specific swizzle withholds native transport, so no real callback can race
    /// the injected schedule. The separate ServerMock tests exercise actual native transport.
    private func assertPreparationCallbacks(
        mode: TrackingMode,
        chunks: [Data],
        laterData: Data?,
        expectedData: Data?,
        completeDuringPreparation: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = try XCTUnwrap(URL(string: "https://example.com/preparation-callbacks"))
        let delegate = SessionDataDelegateMock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Session-Configuration": "preserved"]
        let session = URLSession(configuration: configuration, delegate: mode == .registeredDelegate ? delegate : nil, delegateQueue: nil)
        let task = session.dataTask(with: url)
        defer { session.invalidateAndCancel() }
        let forwarding = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { [weak feature, weak task] candidate, continuation in
            guard candidate === task else {
                continuation()
                return
            }
            forwarding.mutate { $0 += 1 }
            if let laterData { feature?.task(candidate, didReceive: laterData) }
            if !completeDuringPreparation { feature?.task(candidate, didCompleteWithError: nil) }
        }
        defer { previous.unswizzle() }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.shouldInterceptRequest = { $0.url == url }
        let order = ReadWriteLock(wrappedValue: [String]())
        handler.onInterceptionDidStart = { _ in order.mutate { $0.append("start") } }
        handler.onInterceptionDidComplete = { _ in order.mutate { $0.append("complete") } }
        weak var weakPreparation: AnyObject?
        handler.onRequestMutation = { [weak feature, weak task] request, _, _ in
            guard request.url == url, let feature, let task else {
                return
            }
            if completeDuringPreparation {
                weakPreparation = try? Self.preparation(for: task, in: feature)
                XCTAssertNotNil(weakPreparation, "The active preparation must exist", file: file, line: line)
            }
            chunks.forEach { feature.task(task, didReceive: $0) }
            feature.task(task, didFinishCollecting: .mockWith())
            if completeDuringPreparation { feature.task(task, didCompleteWithError: nil) }
            feature.flush()
            XCTAssertTrue(order.wrappedValue.isEmpty, "Callbacks must wait for request preparation", file: file, line: line)
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        if mode == .registeredDelegate {
            try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        }

        task.resume()
        feature.flush()

        if completeDuringPreparation {
            XCTAssertNil(weakPreparation, "Early completion must release the preparation while the task remains alive", file: file, line: line)
            XCTAssertNil(try Self.preparation(for: task, in: feature), file: file, line: line)
        }
        XCTAssertEqual(forwarding.wrappedValue, 1, file: file, line: line)
        XCTAssertEqual(task.state, .suspended, "Native transport is deliberately withheld", file: file, line: line)
        XCTAssertEqual(order.wrappedValue, ["start", "complete"], file: file, line: line)
        XCTAssertEqual(handler.interceptions.count, 1, file: file, line: line)
        let interception = try XCTUnwrap(handler.interceptions.first?.value, file: file, line: line)
        XCTAssertEqual(interception.trackingMode, mode, file: file, line: line)
        XCTAssertEqual(interception.data, expectedData, file: file, line: line)
        XCTAssertNotNil(interception.metrics, file: file, line: line)
        XCTAssertNotNil(interception.completion, file: file, line: line)
        XCTAssertEqual(interception.request.unsafeOriginal.value(forHTTPHeaderField: "X-Session-Configuration"), "preserved", file: file, line: line)
        handler.onRequestMutation = nil
    }

    func testPreparation_terminalCallbackBeforeFirstResumeDoesNotCreateAnInterception() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let server = ServerMock(delivery: .success(response: .mockWith(statusCode: 200), data: Data([1])), skipIsMainThreadCheck: true)
        scopeHandler(to: server)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.onRequestMutation = { _, _, _ in mutations.mutate { $0 += 1 } }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession()
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: URL(string: "https://example.com/terminal-before-resume")!)

        feature.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
        feature.flush()
        XCTAssertEqual(task.state, .suspended, "The terminal callback precedes the native state setter")
        task.resume()
        _ = server.waitAndReturnRequests(count: 1)
        feature.flush()

        XCTAssertEqual(mutations.wrappedValue, 0)
        XCTAssertTrue(handler.interceptions.isEmpty)
    }

    func testPreparation_terminalCallbackRemovesPreparationBeforeNativeStateChanges() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = URL(string: "https://example.com/terminal-preparation-release")!
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        defer { session.invalidateAndCancel() }
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { [weak task] candidate, continuation in
            guard candidate === task else {
                continuation()
                return
            }
            forwarded.mutate { $0 += 1 }
        }
        defer { previous.unswizzle() }
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.shouldInterceptRequest = { $0.url == url }
        handler.onRequestMutation = { request, _, _ in
            guard request.url == url else {
                return
            }
            mutations.mutate { $0 += 1 }
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        task.resume()
        feature.flush()
        XCTAssertNotNil(try Self.preparation(for: task, in: feature))
        feature.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
        feature.flush()

        XCTAssertEqual(task.state, .suspended, "The callback precedes the native state setter")
        XCTAssertNil(try Self.preparation(for: task, in: feature), "Terminal identity must not retain a preparation")
        task.resume()
        feature.flush()
        XCTAssertNil(try Self.preparation(for: task, in: feature))
        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(forwarded.wrappedValue, 2)
        XCTAssertEqual(handler.interceptions.count, 1)
        XCTAssertNotNil(handler.interceptions.first?.value.completion)
    }

    func testPreparation_terminalIdentityIsScopedToFeature() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = URL(string: "https://example.com/feature-terminal-identity")!
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        defer { session.invalidateAndCancel() }
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { [weak task] candidate, continuation in
            guard candidate === task else {
                continuation()
                return
            }
            forwarded.mutate { $0 += 1 }
        }
        defer { previous.unswizzle() }
        let firstMutations = ReadWriteLock(wrappedValue: 0)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.shouldInterceptRequest = { $0.url == url }
        handler.onRequestMutation = { request, _, _ in
            guard request.url == url else {
                return
            }
            firstMutations.mutate { $0 += 1 }
        }
        feature.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
        feature.flush()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        weak var releasedFeature: NetworkInstrumentationFeature?

        try autoreleasepool {
            let secondCore = SingleFeatureCoreMock<NetworkInstrumentationFeature>()
            let secondHandler = URLSessionHandlerMock()
            let secondMutations = ReadWriteLock(wrappedValue: 0)
            secondHandler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
            secondHandler.shouldInterceptRequest = { $0.url == url }
            secondHandler.onRequestMutation = { request, _, _ in
                guard request.url == url else {
                    return
                }
                secondMutations.mutate { $0 += 1 }
            }
            try secondCore.register(urlSessionHandler: secondHandler)
            let secondFeature = try XCTUnwrap(secondCore.get(feature: NetworkInstrumentationFeature.self))
            releasedFeature = secondFeature
            try URLSessionInstrumentation.enableOrThrow(with: nil, in: secondCore)

            task.resume()
            secondFeature.task(task, didCompleteWithError: nil)
            secondFeature.flush()
            task.resume()
            feature.flush()
            secondFeature.flush()

            XCTAssertEqual(firstMutations.wrappedValue, 0)
            XCTAssertTrue(handler.interceptions.isEmpty)
            XCTAssertEqual(secondMutations.wrappedValue, 1)
            XCTAssertEqual(secondHandler.interceptions.count, 1)
            XCTAssertNotNil(secondHandler.interceptions.first?.value.completion)
            XCTAssertEqual(forwarded.wrappedValue, 2)
        }
        XCTAssertNil(releasedFeature, "A live completed task must not retain a different SDK feature")
        XCTAssertEqual(task.state, .suspended)
    }

    /// Observes ownership without adding a production test hook or keeping the record alive.
    private static func preparation(for task: URLSessionTask, in feature: NetworkInstrumentationFeature) throws -> AnyObject? {
        let featureFields = Mirror(reflecting: feature).children
        let coordinator = try XCTUnwrap(featureFields.first { $0.label == "taskPreparation" }?.value)
        let fields = Mirror(reflecting: coordinator).children
        let lock = try XCTUnwrap(fields.first { $0.label == "lock" }?.value as? NSLock)
        let table = try XCTUnwrap(fields.first { $0.label == "preparations" }?.value as? NSMapTable<AnyObject, AnyObject>)
        lock.lock()
        defer { lock.unlock() }
        return table.object(forKey: task)
    }

    func testPreparation_terminalRecordsDoNotRetainTasksOrFeature() throws {
        weak var weakTask: URLSessionTask?
        weak var weakFeature = core.get(feature: NetworkInstrumentationFeature.self)
        try autoreleasepool {
            let feature = try XCTUnwrap(weakFeature)
            let task: URLSessionTask = .mockAny()
            weakTask = task
            feature.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
            feature.flush()
        }
        XCTAssertNil(weakTask, "Terminal records must have weak task identity keys")
        core = nil
        XCTAssertNil(weakFeature)
    }

    func testAutomaticMode_whenTaskFails_itReleasesTerminalOwnership() throws {
        try assertTerminalOwnership(mode: .automatic, cancelDuringPreparation: false)
    }

    func testRegisteredDelegate_whenTaskFails_itReleasesTerminalOwnership() throws {
        try assertTerminalOwnership(mode: .registeredDelegate, cancelDuringPreparation: false)
    }

    func testAutomaticMode_whenTaskIsCancelled_itReleasesTerminalOwnership() throws {
        try assertTerminalOwnership(mode: .automatic, cancelDuringPreparation: true)
    }

    func testRegisteredDelegate_whenTaskIsCancelled_itReleasesTerminalOwnership() throws {
        try assertTerminalOwnership(mode: .registeredDelegate, cancelDuringPreparation: true)
    }

    private func assertTerminalOwnership(
        mode: TrackingMode,
        cancelDuringPreparation: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        weak var weakTask: URLSessionTask?
        weak var weakPreparation: AnyObject?
        weak var weakInterception: URLSessionTaskInterception?
        weak var weakFeature = core.get(feature: NetworkInstrumentationFeature.self)
        weak var weakHandler = handler
        let expectedCode = cancelDuringPreparation ? NSURLErrorCancelled : NSURLErrorNetworkConnectionLost
        let started = expectation(description: "Interception starts once")
        let completed = expectation(description: "Interception completes once")
        let nativeCompleted = expectation(description: "Native task completes")
        let invalidated = expectation(description: "Native session invalidates")

        try autoreleasepool {
            let feature = try XCTUnwrap(weakFeature, file: file, line: line)
            let server = ServerMock(
                delivery: .failure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)),
                skipIsMainThreadCheck: true
            )
            scopeHandler(to: server)
            let url = URL(string: "https://example.com/terminal-ownership")!
            handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
            handler.onInterceptionDidStart = { interception in
                XCTAssertEqual(interception.trackingMode, mode, file: file, line: line)
                started.fulfill()
            }
            handler.onInterceptionDidComplete = { interception in
                weakInterception = interception
                XCTAssertEqual((interception.completion?.error as NSError?)?.code, expectedCode, file: file, line: line)
                XCTAssertEqual(interception.metrics != nil, mode == .registeredDelegate, file: file, line: line)
                completed.fulfill()
            }
            try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
            if mode == .registeredDelegate {
                try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: TerminalLifetimeDelegate.self), in: core)
            }
            let delegate = TerminalLifetimeDelegate { invalidated.fulfill() }
            let session = server.getInterceptedURLSession(delegate: delegate)
            defer { session.invalidateAndCancel() }
            var task: URLSessionDataTask? = session.dataTask(with: url) { _, _, error in
                XCTAssertEqual((error as NSError?)?.code, expectedCode, file: file, line: line)
                nativeCompleted.fulfill()
            }
            weakTask = task
            handler.onRequestMutation = { [weak feature, weak task] request, _, _ in
                guard request.url == url, let feature, let task else {
                    return
                }
                weakPreparation = try? Self.preparation(for: task, in: feature)
                XCTAssertNotNil(weakPreparation, "Observe the preparation before terminal cleanup", file: file, line: line)
                if cancelDuringPreparation { task.cancel() }
            }

            task?.resume()
            wait(for: [started, completed, nativeCompleted], timeout: 5)
            feature.flush()
            _ = server.waitAndReturnRequests(count: cancelDuringPreparation ? 0 : 1, timeout: cancelDuringPreparation ? 0.05 : 5)
            XCTAssertEqual(task?.state, .completed, file: file, line: line)
            XCTAssertNil(weakPreparation, "A live completed task must not retain preparation", file: file, line: line)
            XCTAssertNil(try Self.preparation(for: XCTUnwrap(task), in: feature), file: file, line: line)
            XCTAssertEqual(try Self.activeInterceptionCount(in: feature), 0, "Terminal cleanup removes the feature's task owner", file: file, line: line)
            XCTAssertNotNil(weakInterception, "The recording handler still owns the completed interception", file: file, line: line)
            XCTAssertEqual(handler.interceptions.count, 1, file: file, line: line)

            // Drop the recording mock's explicit ownership while the SDK feature and task are live.
            feature.handlers.removeAll()
            handler = nil
            XCTAssertNil(weakHandler, file: file, line: line)
            XCTAssertNil(weakInterception, "The SDK must not keep a completed interception", file: file, line: line)
            task = nil
            session.finishTasksAndInvalidate()
            wait(for: [invalidated], timeout: 5)
            session.delegateQueue.waitUntilAllOperationsAreFinished()
            feature.flush()
        }
        let taskReleased = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in weakTask == nil }, object: nil)
        wait(for: [taskReleased], timeout: 5)
        XCTAssertNil(weakTask, "Native teardown must release the task", file: file, line: line)
        XCTAssertNotNil(weakFeature, "The core still owns the feature", file: file, line: line)
        core = nil
        XCTAssertNil(weakFeature, "Completed tasks must not keep the feature alive", file: file, line: line)
    }

    private static func activeInterceptionCount(in feature: NetworkInstrumentationFeature) throws -> Int {
        let queue = try XCTUnwrap(Mirror(reflecting: feature).children.first { $0.label == "queue" }?.value as? DispatchQueue)
        return try queue.sync {
            let entries = try XCTUnwrap(Mirror(reflecting: feature).children.first { $0.label == "interceptions" }?.value as? [URLSessionTask: URLSessionTaskInterception])
            return entries.count
        }
    }

    private final class TerminalLifetimeDelegate: NSObject, URLSessionDataDelegate {
        private let onInvalidation: () -> Void

        init(onInvalidation: @escaping () -> Void) {
            self.onInvalidation = onInvalidation
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { }
        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { }
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            onInvalidation()
        }
    }

    func testPreparation_nilCurrentRequestUsesPreparedFallback() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let request = URLRequest(url: URL(string: "https://example.com/prepared-fallback")!)
        let task = MissingCurrentRequestTask()
        XCTAssertNil(task.currentRequest)

        feature.intercept(task: task, with: [], additionalFirstPartyHosts: nil, trackingMode: .automatic, fallbackRequest: request)
        feature.task(task, didCompleteWithError: nil)
        feature.flush()

        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(interception.request.unsafeOriginal, request)
        XCTAssertNotNil(interception.completion)
    }

    func testPreparation_currentRequestTakesPrecedenceOverPreparedFallback() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Session-Configuration": "preserved"]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/current-request")!)
        let currentRequest = try XCTUnwrap(task.currentRequest)
        let fallbackRequest = URLRequest(url: URL(string: "https://example.com/prepared-fallback")!)

        feature.intercept(task: task, with: [], additionalFirstPartyHosts: nil, trackingMode: .automatic, fallbackRequest: fallbackRequest)
        feature.task(task, didCompleteWithError: nil)
        feature.flush()

        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(interception.request.unsafeOriginal, currentRequest)
        XCTAssertEqual(interception.request.unsafeOriginal.value(forHTTPHeaderField: "X-Session-Configuration"), "preserved")
        XCTAssertNotNil(interception.completion)
    }

    func testPreparation_payloadDestructionCanResumeWithoutReinstrumenting() throws {
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let url = URL(string: "https://example.com/reentrant-payload-release")!
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        defer { session.invalidateAndCancel() }
        let forwarding = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { [weak task] candidate, continuation in
            guard candidate === task else {
                continuation()
                return
            }
            forwarding.mutate { $0 += 1 }
        }
        defer { previous.unswizzle() }
        let dataReleased = expectation(description: "Data release can resume")
        let errorReleased = expectation(description: "Error release can resume")
        let mutations = ReadWriteLock(wrappedValue: 0)
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        // Do not retain the completed interception in the handler mock.
        handler.shouldInterceptRequest = { _ in false }
        handler.onRequestMutation = { [weak feature, weak task] request, _, _ in
            guard request.url == url, let feature, let task else {
                return
            }
            mutations.mutate { $0 += 1 }
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: 4_096, alignment: 16)
            pointer.initializeMemory(as: UInt8.self, repeating: 1, count: 4_096)
            let data = Data(bytesNoCopy: pointer, count: 4_096, deallocator: .custom { [weak task] buffer, _ in
                buffer.deallocate()
                task?.resume()
                dataReleased.fulfill()
            })
            feature.task(task, didReceive: data)
            feature.task(task, didCompleteWithError: ReenteringError { [weak task] in
                task?.resume()
                errorReleased.fulfill()
            })
        }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        task.resume()
        feature.flush()
        wait(for: [dataReleased, errorReleased], timeout: 5)
        feature.flush()

        XCTAssertEqual(mutations.wrappedValue, 1)
        XCTAssertEqual(forwarding.wrappedValue, 3)
        XCTAssertEqual(task.state, .suspended)
        handler.onRequestMutation = nil
    }

    func testPreparation_rebindingDelegatePreservesCompletedTaskAndStartsNewTaskOnce() throws {
        let (server, started, completed) = setupInterceptionTest(expectedFulfillmentCount: 2)
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let mutations = ReadWriteLock(wrappedValue: 0)
        let completions = ReadWriteLock(wrappedValue: 0)
        let firstCompleted = expectation(description: "First task finishes before rebind")
        let existingCompletion = handler.onInterceptionDidComplete
        handler.onInterceptionDidComplete = { interception in
            existingCompletion?(interception)
            var isFirst = false
            completions.mutate { $0 += 1; isFirst = $0 == 1 }
            if isFirst { firstCompleted.fulfill() }
        }
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]])
        handler.onRequestMutation = { _, _, _ in mutations.mutate { $0 += 1 } }
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: SessionDataDelegateMock())
        defer { session.finishTasksAndInvalidate() }
        let first = session.dataTask(with: URL(string: "https://example.com/rebind-first")!)
        first.resume()
        wait(for: [firstCompleted], timeout: 5)
        feature.flush()

        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        first.resume()
        let second = session.dataTask(with: URL(string: "https://example.com/rebind-second")!)
        second.resume()
        second.resume()
        wait(for: [started, completed], timeout: 5)
        feature.flush()
        _ = server.waitAndReturnRequests(count: 2)

        XCTAssertEqual(mutations.wrappedValue, 2)
        XCTAssertEqual(handler.interceptions.count, 2)
        XCTAssertTrue(handler.interceptions.values.allSatisfy { $0.trackingMode == .registeredDelegate && $0.metrics != nil && $0.completion != nil })
    }

    private final class ReenteringError: Error, @unchecked Sendable {
        let onRelease: () -> Void
        init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
        deinit { onRelease() }
    }

    private final class MissingCurrentRequestTask: URLSessionDataTask, @unchecked Sendable {
        override var currentRequest: URLRequest? { nil }
    }

    func testAutomaticMode_tracksAsyncAwaitTasks() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given - Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Session without delegate
        let session = server.getInterceptedURLSession()

        // When - using async data API
        let url = URL.mockAny()
        _ = try? await session.data(from: url)

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data should not be captured in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksTaskWithURL() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Session without delegate
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - using data task
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data should not be captured in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksTaskWithURLRequest() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let request = URLRequest(url: URL.mockAny())
        session.dataTask(with: request).resume()

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data should not be captured in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksCombineTasks() throws {
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let cancellable = session.dataTaskPublisher(for: URL.mockAny())
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )

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
        _ = cancellable // extend lifetime of Combine subscription

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Data should be captured via completion handler")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksUploadTaskWithCompletionHandler() throws {
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let task = session.uploadTask(
            with: URLRequest(url: URL.mockAny()),
            from: Data.mockRandom(ofSize: 20)
        ) { _, _, _ in }
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Upload tasks don't capture response data in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksUploadTaskWithoutCompletionHandler() throws {
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let task = session.uploadTask(with: URLRequest(url: URL.mockAny()), from: Data.mockRandom(ofSize: 20))
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data should not be captured in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testAutomaticMode_tracksAsyncUploadTasks() async throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - Use async/await upload API
        _ = try? await session.upload(for: URLRequest(url: URL.mockAny()), from: Data.mockRandom(ofSize: 20))

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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data is not captured when using Async API")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_tracksDownloadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - using download task
        let task = session.downloadTask(with: URL.mockAny())
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Download task should use automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data not captured in automatic mode for download tasks")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testAutomaticMode_doesNotCaptureMetricsEvenWithDelegate() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable ONLY automatic mode (don't register delegate for metrics)
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Session has a delegate, but it's not a registered delegate class
        let delegate = SessionDataDelegateMock()
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data is not captured in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    // MARK: - Both Modes Enabled

    func testGivenBothModesEnabled_whenSessionDoesNotRegisterDelegate_itInterceptsAutomatically() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Both modes enabled, but session doesn't use registered delegate
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)
        let session = server.getInterceptedURLSession() // no delegate

        // When
        let url: URL = .mockRandom()
        session.dataTask(with: url).resume()

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

        XCTAssertEqual(handler.interceptions.count, 1, "Task should be intercepted")

        // Verify automatic mode is used for tasks without registered delegate
        let interception = try XCTUnwrap(handler.interception(for: url))

        XCTAssertEqual(interception.trackingMode, .automatic, "Task without registered delegate should use automatic mode")

        // Automatic mode should NOT capture metrics or data without completion handler
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data not captured in automatic mode")

        // But should capture response size and completion
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")

        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenPerTaskDelegate_itUsesCorrectTrackingMode() throws {
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let server = ServerMock(
            delivery: .success(response: .mockWith(statusCode: 200, mimeType: "application/json"), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )
        scopeHandler(to: server)

        // Given - Enable both automatic and registered delegate modes (reflects real-world usage)
        let delegate1 = MockDelegate()
        let delegate2 = MockDelegate2()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core) // Registered delegate

        let session = server.getInterceptedURLSession()

        // When
        let url1 = URL.mockWith(url: "https://www.foo.com/1")
        let task1 = session.dataTask(with: url1) // intercepted by registered delegate mode
        task1.delegate = delegate1
        task1.resume()

        let url2 = URL.mockWith(url: "https://www.foo.com/2")
        let task2 = session.dataTask(with: url2) // intercepted by automatic mode
        task2.delegate = delegate2
        task2.resume()

        // Then
        wait(
            for: [
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 2)
        XCTAssertEqual(handler.interceptions.count, 2, "All tasks should be intercepted")

        // Verify tracking modes are correct based on delegate type

        let interception1 = try XCTUnwrap(handler.interception(for: url1))
        XCTAssertEqual(interception1.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception1.metrics, "Should capture metrics with registered delegate")
        XCTAssertEqual(interception1.data?.count, 10, "Should capture data with registered delegate")

        let interception2 = try XCTUnwrap(handler.interception(for: url2))
        XCTAssertEqual(interception2.trackingMode, .automatic, "Task without registered delegate should be in automatic mode")
        XCTAssertNil(interception2.metrics, "Should not capture metrics in automatic mode")
        XCTAssertNil(interception2.data, "Should not capture data in automatic mode")
        XCTAssertEqual(interception2.responseSize, 10, "Should capture response size in automatic mode")
        XCTAssertNotNil(interception2.completion, "Should capture completion")
        XCTAssertNotNil(interception2.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception2.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenSessionWithDelegateAndCompletionHandler_itCapturesMetrics() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both automatic and registered delegate modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core) // Registered delegate

        let delegate = SessionDataDelegateMock()
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in }
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

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Registered delegate mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Data size should match expected size")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testGivenBothModesEnabled_whenRegisteredDelegateWithCompletionHandler_itCapturesMetricsAndData() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes
        let registeredDelegate = MockDelegate()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task with registered delegate AND completion handler
        let url = URL.mockAny()
        let task = session.dataTask(with: url) { _, _, _ in }
        task.delegate = registeredDelegate
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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via completion handler")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testGivenBothModesEnabled_whenRegisteredDelegateWithoutCompletionHandler_itCapturesMetricsAndData() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes
        let registeredDelegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task with registered delegate WITHOUT completion handler
        let url = URL.mockAny()
        let task = session.dataTask(with: url)
        task.delegate = registeredDelegate
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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Should use registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via delegate didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testGivenBothModesEnabled_whenUnregisteredDelegateWithCompletionHandler_itUsesAutomaticMode() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes, but task uses unregistered delegate
        let unregisteredDelegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task with unregistered delegate AND completion handler
        let url = URL.mockAny()
        let task = session.dataTask(with: url) { _, _, _ in }
        task.delegate = unregisteredDelegate
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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .automatic, "Should use automatic mode for unregistered delegate")
        XCTAssertNil(interception.metrics, "Should not capture metrics in automatic mode")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via completion handler without double-counting")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenUnregisteredDelegateWithoutCompletionHandler_itUsesAutomaticMode() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes, but task uses unregistered delegate
        let unregisteredDelegate = MockDelegate2()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task with unregistered delegate WITHOUT completion handler
        let url = URL.mockAny()
        let task = session.dataTask(with: url)
        task.delegate = unregisteredDelegate
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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .automatic, "Should use automatic mode for unregistered delegate")
        XCTAssertNil(interception.metrics, "Should not capture metrics in automatic mode")
        XCTAssertNil(interception.data, "Should not capture data without completion handler in automatic mode")
        XCTAssertNotNil(interception.responseSize, "Should capture response size via setState")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenNoDelegateWithCompletionHandler_itUsesAutomaticMode() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task without delegate AND with completion handler
        let url = URL.mockAny()
        session.dataTask(with: url) { _, _, _ in }.resume()

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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .automatic, "Should use automatic mode when no delegate")
        XCTAssertNil(interception.metrics, "Should not capture metrics in automatic mode")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via completion handler without double-counting")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenNoDelegateWithoutCompletionHandler_itUsesAutomaticMode() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable both modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core)

        let session = server.getInterceptedURLSession()

        // When - Task without delegate and WITHOUT completion handler
        let url = URL.mockAny()
        session.dataTask(with: url).resume()

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

        let interception = try XCTUnwrap(handler.interception(for: url))
        XCTAssertEqual(interception.trackingMode, .automatic, "Should use automatic mode when no delegate")
        XCTAssertNil(interception.metrics, "Should not capture metrics in automatic mode")
        XCTAssertNil(interception.data, "Should not capture data without completion handler in automatic mode")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testGivenBothModesEnabled_whenUsingAsyncAPI_itCapturesAllValues() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true, expectedFulfillmentCount: 2)

        // Given - Enable both modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        let session = server.getInterceptedURLSession() // No session-level delegate

        // When - Using Async/await API
        let url1: URL = .mockRandom()
        _ = try? await session.data(from: url1, delegate: delegate) // Registered Delegate mode
        let url2: URL = .mockRandom()
        _ = try? await session.data(from: url2) // Automatic mode (no delegate)

        // Then
        await dd_fulfillment(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        _ = server.waitAndReturnRequests(count: 2)

        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should record 2 tasks")

        let interception1 = try XCTUnwrap(handler.interception(for: url1))
        XCTAssertEqual(interception1.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
        XCTAssertNotNil(interception1.metrics, "Task with registered delegate should collect metrics")
        XCTAssertNil(interception1.data, "Data should not be recorded for tasks with no completion handler")
        XCTAssertEqual(interception1.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception1.completion, "Should capture completion")

        let interception2 = try XCTUnwrap(handler.interception(for: url2))
        XCTAssertEqual(interception2.trackingMode, .automatic, "Task with no registered delegate should be in automatic mode")
        XCTAssertNil(interception2.metrics, "Task in automatic mode should not collect metrics")
        XCTAssertNil(interception2.data, "Data should not be recorded for tasks with no completion handler")
        XCTAssertEqual(interception2.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception2.completion, "Should capture completion")
        XCTAssertNotNil(interception2.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception2.endDate, "Should capture approximate end date")
    }

    func testGivenBothModesEnabled_whenUsingDownloadTask_itUsesCorrectTrackingMode() throws {
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )
        scopeHandler(to: server)

        // Given - Both modes enabled
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core) // Registered Delegate mode

        let session = server.getInterceptedURLSession()

        // When - Download task with per-task delegate (Registered Delegate mode)
        let url1 = URL.mockWith(url: "https://www.foo.com/download1")
        let task1 = session.downloadTask(with: url1)
        task1.delegate = delegate
        task1.resume()

        // Download task without delegate (Automatic mode)
        let url2 = URL.mockWith(url: "https://www.foo.com/download2")
        let task2 = session.downloadTask(with: url2)
        task2.resume()

        // Then
        wait(for: [notifyInterceptionDidComplete], timeout: 5)
        _ = server.waitAndReturnRequests(count: 2)

        // Verify task with delegate uses registered delegate mode
        let interception1 = try XCTUnwrap(handler.interception(for: url1))
        XCTAssertEqual(interception1.trackingMode, .registeredDelegate, "Download task with registered per-task delegate should use registered delegate mode")
        XCTAssertNotNil(interception1.metrics, "Should capture metrics")
        XCTAssertNil(interception1.data, "Data not captured for download tasks")
        XCTAssertEqual(interception1.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception1.completion, "Should capture completion")

        // Verify task without delegate uses automatic mode
        let interception2 = try XCTUnwrap(handler.interception(for: url2))
        XCTAssertEqual(interception2.trackingMode, .automatic, "Download task without delegate should use automatic mode")
        XCTAssertNil(interception2.metrics, "Should not capture metrics in automatic mode")
        XCTAssertNil(interception2.data, "Data not captured for download tasks")
        XCTAssertEqual(interception2.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception2.completion, "Should capture completion")
        XCTAssertNotNil(interception2.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception2.endDate, "Should capture approximate end date")
    }

    // MARK: - Content Validation

    func testAutomaticMode_whenTaskIsCancelled_itCapturesError() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Use real URLSession (not mock) to test actual cancellation behavior
        let session = URLSession(configuration: .ephemeral)

        // When - Create task to an unreachable IP address (TEST-NET-1, guaranteed to not respond quickly)
        // This ensures the task will still be running when we cancel it
        let url = URL(string: "https://192.0.2.0:9999")! // TEST-NET-1: Reserved for documentation, never responds
        let task = session.dataTask(with: url)
        task.resume()
        task.cancel() // Cancel the task while it's still running

        // Then
        wait(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.trackingMode, .automatic, "Task should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture URLSessionTaskMetrics")

        let completion = try XCTUnwrap(interception.completion, "Should capture completion")
        let error = try XCTUnwrap(completion.error, "Should capture cancellation error") as NSError
        XCTAssertEqual(error.domain, NSURLErrorDomain, "Error should be NSURLError")
        XCTAssertEqual(error.code, NSURLErrorCancelled, "Error should be NSURLErrorCancelled")
    }

    func testGivenRegisteredDelegate_whenTaskCompletesWithFailure_itCapturesError() throws {
        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let (server, _, _) = setupInterceptionTest(error: expectedError)

        let dateBeforeRequest = Date()

        // Given
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url = URL.mockRandom()
        session.dataTask(with: url).resume()

        // Then
        _ = server.waitAndReturnRequests(count: 1)

        waitForExpectations(timeout: 5, handler: nil)
        let dateAfterRequest = Date()

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Registered delegate mode captures metrics and completion (even on failure)
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")

        let metrics = try XCTUnwrap(interception.metrics, "Should capture metrics even on failure")
        XCTAssertGreaterThan(metrics.fetch.start, dateBeforeRequest)
        XCTAssertLessThan(metrics.fetch.end, dateAfterRequest)

        // Data is NOT captured without completion handler
        XCTAssertNil(interception.data, "Data not captured without completion handler")

        // Error is captured via setState
        let completion = try XCTUnwrap(interception.completion, "Should capture completion")
        XCTAssertEqual((completion.error as? NSError)?.localizedDescription, "some error")
    }

    func testGivenRegisteredDelegate_whenTaskCompletesWithSuccess_itCapturesAllValues() throws {
        let (server, _, _) = setupInterceptionTest()

        let dateBeforeRequest = Date()

        // Given
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url = URL.mockRandom()
        session.dataTask(with: url).resume()

        // Then
        _ = server.waitAndReturnRequests(count: 1)

        waitForExpectations(timeout: 5, handler: nil)
        let dateAfterRequest = Date()

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Registered delegate mode captures metrics and completion
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")

        let metrics = try XCTUnwrap(interception.metrics, "Should capture metrics")
        XCTAssertGreaterThan(metrics.fetch.start, dateBeforeRequest)
        XCTAssertLessThan(metrics.fetch.end, dateAfterRequest)

        // Data is captured with registered delegate via didReceive delegate swizzling
        XCTAssertNotNil(interception.data, "Data should be captured with registered delegate via didReceive swizzling")
        XCTAssertNotNil(interception.responseSize, "Should capture response size")
        XCTAssertGreaterThan(interception.responseSize ?? 0, 0, "Response size should be greater than 0")

        // Completion is captured via setState
        let completion = try XCTUnwrap(interception.completion, "Should capture completion")
        XCTAssertNil(completion.error, "Should capture no error")
    }

    func testGivenAutomaticMode_whenTaskWithoutCompletionHandler_itCapturesBasicValues() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Enable only automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - Task WITHOUT completion handler
        let url = URL.mockRandom()
        session.dataTask(with: url).resume()

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

        XCTAssertEqual(handler.interceptions.count, 1, "Should capture 1 interception")

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Automatic mode captures basic values
        XCTAssertEqual(interception.trackingMode, .automatic, "Should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture detailed metrics")

        // Duration: captured via setState
        XCTAssertNotNil(interception.completion, "Should capture completion for duration")

        // Status: captured via task.response in setState
        XCTAssertEqual(interception.completion?.httpResponse?.statusCode, 200, "Should capture status code")

        // Size: captured via task.countOfBytesReceived in setState
        XCTAssertNotNil(interception.responseSize, "Should capture response size for automatic mode")
        XCTAssertGreaterThan(interception.responseSize ?? 0, 0, "Response size should be greater than 0")
        // Data itself is NOT captured without completion handler or delegate
        XCTAssertNil(interception.data, "Data not captured without completion handler or delegate")

        // Errors: captured via task.error in setState
        XCTAssertNil(interception.completion?.error, "Should capture error status")

        // Request: captured
        XCTAssertEqual(interception.request.url, url, "Should capture request URL")
    }

    func testGivenAutomaticMode_whenTaskWithCompletionHandler_itCapturesAllBasicValues() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")

        let randomData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: randomData), skipIsMainThreadCheck: true)

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }
        scopeHandler(to: server)

        // Given - Enable only automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - Task WITH completion handler
        let url = URL.mockRandom()
        session.dataTask(with: url) { _, _, _ in }.resume()

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

        XCTAssertEqual(handler.interceptions.count, 1, "Should capture 1 interception")

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Automatic mode captures all basic values when completion handler is present
        XCTAssertEqual(interception.trackingMode, .automatic, "Should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture detailed metrics")

        // Duration: captured
        let completion = try XCTUnwrap(interception.completion, "Should capture completion for duration")

        // Status: captured
        XCTAssertEqual(completion.httpResponse?.statusCode, 200, "Should capture status code")

        // Size: captured via completion handler data
        XCTAssertEqual(interception.data, randomData, "Should capture response data via completion handler")
        XCTAssertNotNil(interception.responseSize, "Should capture response size")

        // Errors: captured
        XCTAssertNil(completion.error, "Should capture error status")

        // Request: captured
        XCTAssertEqual(interception.request.url, url, "Should capture request URL")
    }

    func testGivenAutomaticMode_whenTaskCompletesWithFailure_itCapturesError() throws {
        let testError = NSError(domain: "test", code: 123, userInfo: nil)
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(error: testError)

        // Given - Enable only automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - Task that fails with error
        let url = URL.mockRandom()
        session.dataTask(with: url).resume()

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

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Should capture error
        XCTAssertEqual(interception.trackingMode, .automatic, "Should be in automatic mode")
        XCTAssertNil(interception.metrics, "Automatic mode should not capture metrics")
        XCTAssertNil(interception.data, "Data not captured when task fails")
        XCTAssertEqual(interception.responseSize, 0, "Response size should be 0 for failed tasks")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
        let completion = try XCTUnwrap(interception.completion, "Should capture completion")
        XCTAssertNotNil(completion.error, "Should capture error")
        XCTAssertEqual((completion.error as? NSError)?.code, 123, "Should capture correct error code")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testGivenRegisteredDelegate_whenUsingAsyncAPI_itCapturesAllValues() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(error: expectedError, skipIsMainThreadCheck: true, expectedFulfillmentCount: 2)

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        let session = server.getInterceptedURLSession()

        // When
        _ = try? await session.data(from: .mockRandom(), delegate: delegate) // intercepted
        _ = try? await session.data(for: URLRequest(url: .mockRandom()), delegate: delegate) // intercepted

        // Then
        await dd_fulfillment(
            for: [
                notifyInterceptionDidStart,
                notifyInterceptionDidComplete
            ],
            timeout: 5,
            enforceOrder: true
        )

        _ = server.waitAndReturnRequests(count: 2)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(handler.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        handler.interceptions.forEach { id, interception in
            XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Task with registered delegate should use registered delegate mode")
            XCTAssertNotNil(interception.metrics, "Should capture metrics for \(id)")
            XCTAssertGreaterThan(interception.metrics?.fetch.start ?? .distantPast, dateBeforeAnyRequests)
            XCTAssertLessThan(interception.metrics?.fetch.end ?? .distantFuture, dateAfterAllRequests)
            XCTAssertNil(interception.data, "Data should not be recorded for \(id)")
            XCTAssertEqual(interception.responseSize, 0, "Response size should be 0 for failed tasks")
            XCTAssertNotNil(interception.completion, "Should capture completion for \(id)")
            XCTAssertEqual((interception.completion?.error as? NSError)?.localizedDescription, "some error")
        }
    }

    // MARK: - Usage

    func testAutomaticMode_enabledOnlyOnce() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // When - Try to enable again
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Then - Should not crash or cause issues (idempotent)
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        XCTAssertNotNil(feature)
    }

    func testWhenEnableAutomaticModeTwice_thenItPrintsAWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Then
        XCTAssertEqual(
            dd.logger.debugLog?.message,
            "Automatic network instrumentation is already enabled."
        )
    }

    func testWhenEnablingDurationBreakdownOnTheSameDelegate_thenItPrintsAWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Then
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            The delegate class SessionDataDelegateMock is already instrumented.
            The previous instrumentation will be disabled in favor of the new one.
            """
        )
    }

    func testWhenEnablingDurationBreakdownBeforeAutomaticMode_thenItPrintsAnError() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When - Try to enable duration breakdown without enabling automatic mode first
        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Then
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            Duration breakdown requires automatic network instrumentation to be enabled first.
            Please enable RUM or Trace with `urlSessionTracking` parameter before enabling duration breakdown.
            """
        )
    }

    // MARK: - Filtering Out Intake Requests

    func testAutomaticMode_doesNotTrackSDKRequests() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Create a real URLSession
        let session = URLSession(configuration: .ephemeral)

        // Track if any requests with DD-API-KEY are intercepted
        var interceptedSDKRequests: [URLSessionTaskInterception] = []
        handler.onInterceptionDidStart = { interception in
            interceptedSDKRequests.append(interception)
        }

        // When - Make a request to a custom endpoint with DD-API-KEY header (simulating SDK internal request)
        let customEndpointURL = URL(string: "http://custom-endpoint.example.com/api/v2/intake")!
        var request = URLRequest(url: customEndpointURL)
        request.setValue(.mockRandom(), forHTTPHeaderField: "DD-API-KEY")

        let taskCompleted = expectation(description: "Task completed")
        let task = session.dataTask(with: request) { _, _, _ in
            taskCompleted.fulfill()
        }
        task.resume()
        task.cancel()

        // Wait for the cancellation completion.
        wait(for: [taskCompleted], timeout: 1)

        // Then - Verify SDK request with DD-API-KEY was not intercepted
        XCTAssertEqual(interceptedSDKRequests.count, 0, "Should not intercept SDK requests with DD-API-KEY header, even to custom endpoints")
    }

    func testAutomaticMode_doesNotTrackSDKRequestsAuthenticatedWithClientToken() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let session = URLSession(configuration: .ephemeral)

        var interceptedSDKRequests: [URLSessionTaskInterception] = []
        handler.onInterceptionDidStart = { interception in
            interceptedSDKRequests.append(interception)
        }

        // When - Make a request with DD-CLIENT-TOKEN (used by the profiling quota admission API)
        let quotaURL = URL(string: "http://custom-endpoint.example.com/api/v2/profiling/quota?session_id=test")!
        var request = URLRequest(url: quotaURL)
        request.setValue(.mockRandom(), forHTTPHeaderField: "DD-CLIENT-TOKEN")

        let taskCompleted = expectation(description: "Task completed")
        let task = session.dataTask(with: request) { _, _, _ in
            taskCompleted.fulfill()
        }
        task.resume()
        task.cancel()

        // Wait for the cancellation completion.
        wait(for: [taskCompleted], timeout: 1)

        // Then
        XCTAssertEqual(interceptedSDKRequests.count, 0, "Should not intercept SDK requests with DD-CLIENT-TOKEN header")
    }

    func testAutomaticMode_doesNotTrackSDKRequestsMarkedInternal() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let session = URLSession(configuration: .ephemeral)

        var interceptedSDKRequests: [URLSessionTaskInterception] = []
        handler.onInterceptionDidStart = { interception in
            interceptedSDKRequests.append(interception)
        }

        // When - Make a request to a public CDN endpoint marked internal (e.g. Remote Configuration
        // fetch), which cannot carry DD-API-KEY/DD-CLIENT-TOKEN since those must not reach a public CDN.
        let cdnURL = URL(string: "http://custom-endpoint.example.com/v1/remote-configuration.json")!
        var request = URLRequest(url: cdnURL)
        URLRequestBuilder.markAsInternal(&request)

        let taskCompleted = expectation(description: "Task completed")
        let task = session.dataTask(with: request) { _, _, _ in
            taskCompleted.fulfill()
        }
        task.resume()
        task.cancel()

        // Wait for the cancellation completion.
        wait(for: [taskCompleted], timeout: 1)

        // Then - Verify SDK request marked internal was not intercepted
        XCTAssertEqual(interceptedSDKRequests.count, 0, "Should not intercept SDK requests marked internal via URLRequestBuilder.markAsInternal")
    }

    func testAutomaticMode_doesNotTrackDatadogSDKTestingRequests() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let session = URLSession(configuration: .ephemeral)

        var intercepted: [URLSessionTaskInterception] = []
        handler.onInterceptionDidStart = { intercepted.append($0) }

        // When - Simulate `DatadogSDKTesting`'s CI Visibility upload: it hits citestcycle intake
        // authenticated with `DD-API-KEY` but without our SDK's internal `DD-REQUEST-ID` header.
        let citestcycleURL = URL(string: "https://citestcycle-intake.datadoghq.com/api/v2/citestcycle")!
        var request = URLRequest(url: citestcycleURL)
        request.setValue(.mockRandom(), forHTTPHeaderField: "DD-API-KEY")

        let taskCompleted = expectation(description: "Task completed")
        let task = session.dataTask(with: request) { _, _, _ in taskCompleted.fulfill() }
        task.resume()
        task.cancel()

        wait(for: [taskCompleted], timeout: 5)

        // Then
        XCTAssertEqual(intercepted.count, 0, "Should not intercept DatadogSDKTesting CI Visibility uploads (DD-API-KEY without DD-REQUEST-ID)")
    }

    /// Regression test: the resume swizzle is process-global, so foreign URLSession activity in
    /// the test process (e.g. `DatadogSDKTesting`) was reaching the test handler and over-fulfilling
    /// expectations with `NSInternalInconsistencyException: multiple calls made to -[XCTestExpectation fulfill]`.
    /// `setupInterceptionTest` defends against this via `shouldInterceptRequest`; this test verifies
    /// that a foreign request is not observed.
    func testAutomaticMode_handlerIgnoresForeignURLSessionTraffic() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Foreign URLSession not produced by `ServerMock` — simulates any other framework using
        // URLSession in the same process.
        let foreignSession = URLSession(configuration: .ephemeral)
        let foreignTask = foreignSession.dataTask(with: URL(string: "http://example.invalid/foreign")!)
        foreignTask.resume()
        foreignTask.cancel() // resume hook has already fired; short-circuit any real network IO

        // Real test traffic through the `ServerMock`-backed session.
        let session = server.getInterceptedURLSession()
        let task = session.dataTask(with: URL.mockAny())

        // The rest of this test depends on `httpAdditionalHeaders` having the UUID
        // on `task.currentRequest` so ServerMock can recognize its own session.
        let currentRequest = try XCTUnwrap(task.currentRequest)
        XCTAssertTrue(server.isMyRequest(currentRequest), "ServerMock should recognize its own session's task")

        task.resume()

        wait(
            for: [notifyInterceptionDidStart, notifyInterceptionDidComplete],
            timeout: 5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 1)

        XCTAssertEqual(handler.interceptions.count, 1, "Only the `ServerMock`-backed request should be captured")
        let interception = try XCTUnwrap(handler.interceptions.first).value
        XCTAssertEqual(interception.request.url, URL.mockAny(), "Should be the `ServerMock` task, not the foreign one")
    }

    // MARK: - URLSessionTask Interception

    func testWhenInterceptingTaskWithMultipleTraceContexts_itTakesTheFirstContext() throws {
        let traceContexts = [
            TraceContext(traceID: .mock(1, 1), spanID: .mock(2), parentSpanID: nil, sampleRate: .mockRandom(), samplingPriority: .mockRandom(), samplingDecisionMaker: .mockRandom(), rumSessionId: .mockAny()),
            TraceContext(traceID: .mock(2, 2), spanID: .mock(3), parentSpanID: nil, sampleRate: .mockRandom(), samplingPriority: .mockRandom(), samplingDecisionMaker: .mockRandom(), rumSessionId: .mockAny()),
            TraceContext(traceID: .mock(3, 3), spanID: .mock(4), parentSpanID: nil, sampleRate: .mockRandom(), samplingPriority: .mockRandom(), samplingDecisionMaker: .mockRandom(), rumSessionId: .mockAny()),
        ]

        // When
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        feature.intercept(
            task: .mockAny(),
            with: traceContexts.map { NetworkInstrumentationFeature.RequestInstrumentationContext(traceContext: $0, capturedState: nil) },
            additionalFirstPartyHosts: nil,
            trackingMode: .mockRandom()
        )

        feature.flush()

        // Then
        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(interception.trace, traceContexts.first, "It should register first injected Trace Context")
    }

    // MARK: - isSupportedForInstrumentation

    func testIsSupportedForInstrumentation_returnsTrueForDataTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL.mockAny())
        defer { task.cancel() }
        XCTAssertTrue(task.isSupportedForInstrumentation)
    }

    func testIsSupportedForInstrumentation_returnsTrueForUploadTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.uploadTask(with: URLRequest(url: URL.mockAny()), from: Data())
        defer { task.cancel() }
        XCTAssertTrue(task.isSupportedForInstrumentation)
    }

    func testIsSupportedForInstrumentation_returnsTrueForDownloadTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: URL.mockAny())
        defer { task.cancel() }
        XCTAssertTrue(task.isSupportedForInstrumentation)
    }

    func testIsSupportedForInstrumentation_returnsTrueForWebSocketTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: URL(string: "wss://example.com")!)
        defer { task.cancel() }
        XCTAssertTrue(task.isSupportedForInstrumentation)
    }

    func testIsSupportedForInstrumentation_returnsTrueForStreamTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.streamTask(withHostName: "example.com", port: 80)
        defer { task.cancel() }
        XCTAssertTrue(task.isSupportedForInstrumentation)
    }

    func testIsSupportedForInstrumentation_returnsFalseForUnsupportedAVTaskTypes() {
        let unsupportedClassNames = [
            "AVAssetDownloadTask",
            "NSURLSessionAVAssetDownloadTask",
            "AVAggregateAssetDownloadTask",
            "NSURLSessionAVAggregateAssetDownloadTask",
            "__NSCFBackgroundAVAssetDownloadTask"
        ]
        for className in unsupportedClassNames {
            guard let task = NSClassFromString(className)?.alloc() as? URLSessionTask else {
                continue // class unavailable on this platform/OS version
            }
            XCTAssertFalse(task.isSupportedForInstrumentation, "\(className) should not be instrumented")
        }
    }

    // MARK: - Crash regression: resume() on various task types

    func testWebSocketTask_resumeDoesNotCrash() throws {
        // Regression: verify that resuming a WebSocketTask with the swizzle installed doesn't crash.
        // The crash in interceptResume is synchronous, so no real connection is needed — we cancel immediately.
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: URL(string: "wss://example.com")!)
        task.resume()
        task.cancel()

        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.flush()
        // No crash = pass. WebSocketTask is a supported type and should be tracked.
        XCTAssertEqual(handler.interceptions.count, 1)
    }

    func testStreamTask_resumeDoesNotCrash() throws {
        // Regression: verify that resuming a StreamTask with the swizzle installed doesn't crash.
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = URLSession(configuration: .ephemeral)
        let task = session.streamTask(withHostName: "example.com", port: 80)
        task.resume()
        task.cancel()

        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        feature.flush()
        // No crash = pass. StreamTask is a supported type and should be tracked.
        XCTAssertEqual(handler.interceptions.count, 1)
    }

    // MARK: - First Party Hosts

    func testAutomaticMode_detectsFirstPartyHosts() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)), skipIsMainThreadCheck: true)
        scopeHandler(to: server)

        // Given - Configure first-party hosts
        let url = URL(string: "https://api.example.com")!
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )

        handler.onInterceptionDidStart = { interception in
            // Then - First-party host is detected in automatic mode
            XCTAssertTrue(interception.isFirstPartyRequest, "First-party host should be detected in automatic mode")
            notifyInterceptionDidStart.fulfill()
        }

        // Enable automatic mode only
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let request = URLRequest(url: url)
        session.dataTask(with: request).resume()

        // Then
        waitForExpectations(timeout: 5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testAutomaticMode_injectsTraceHeadersForFirstPartyHosts() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)), skipIsMainThreadCheck: true)
        scopeHandler(to: server)

        // Given - Configure first-party hosts
        let url = URL(string: "https://api.example.com")!
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog, .tracecontext]]
        )

        var capturedHeaderTypes: Set<TracingHeaderType>?
        handler.onRequestMutation = { _, headerTypes, _ in
            capturedHeaderTypes = headerTypes
            notifyRequestMutation.fulfill()
        }
        handler.onInterceptionDidStart = { interception in
            XCTAssertTrue(interception.isFirstPartyRequest, "Should be detected as first-party request")
            notifyInterceptionDidStart.fulfill()
        }

        // Enable automatic mode only
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When
        let request = URLRequest(url: url)
        session.dataTask(with: request).resume()

        // Then - Verify request mutation (header injection) was called with correct header types
        waitForExpectations(timeout: 5, handler: nil)
        XCTAssertEqual(capturedHeaderTypes, [.datadog, .tracecontext], "Should pass configured header types for injection")
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testAutomaticMode_doesNotInjectHeadersForThirdPartyHosts() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)), skipIsMainThreadCheck: true)
        scopeHandler(to: server)

        // Given - Configure first-party hosts that don't match the request URL
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: ["api.first-party.com": [.datadog]]
        )

        var requestMutationCalled = false
        handler.onRequestMutation = { _, _, _ in
            requestMutationCalled = true
        }
        handler.onInterceptionDidStart = { interception in
            XCTAssertFalse(interception.isFirstPartyRequest, "Should NOT be detected as first-party request")
            notifyInterceptionDidStart.fulfill()
        }

        // Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let session = server.getInterceptedURLSession(delegate: nil)

        // When - Request to third-party URL
        let thirdPartyURL = URL(string: "https://api.third-party.com/endpoint")!
        session.dataTask(with: URLRequest(url: thirdPartyURL)).resume()

        // Then - Verify request mutation was NOT called for third-party hosts
        waitForExpectations(timeout: 5, handler: nil)
        XCTAssertFalse(requestMutationCalled, "Should NOT inject headers for third-party hosts")
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testRegisteredDelegate_detectsFirstPartyHosts() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let delegate = SessionDataDelegateMock()
        let firstPartyHosts: URLSessionInstrumentation.FirstPartyHostsTracing = .traceWithHeaders(hostsWithHeaders: ["test.com": [.datadog]])
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self, firstPartyHostsTracing: firstPartyHosts), in: core)

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
        wait(for: [notifyInterceptionDidStart, notifyInterceptionDidComplete], timeout: 5, enforceOrder: true)
        _ = server.waitAndReturnRequests(count: 1)
    }

    // MARK: - GraphQL Header Removal Tests

    func testGivenRequestWithGraphQLHeaders_whenInterceptingRequest_itRemovesGraphQLHeaders() throws {
        // Given
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        let url = URL(string: "https://api.example.com/graphql")!
        handler.firstPartyHosts = .init(hostsWithTracingHeaderTypes: [url.host!: [.datadog]])

        var request = URLRequest(url: url)
        request.setValue("GetUser", forHTTPHeaderField: GraphQLHeaders.operationName)
        request.setValue("query", forHTTPHeaderField: GraphQLHeaders.operationType)
        request.setValue("{\"userId\":\"123\"}", forHTTPHeaderField: GraphQLHeaders.variables)
        request.setValue("query GetUser { user { name } }", forHTTPHeaderField: GraphQLHeaders.payload)

        // When
        let (modifiedRequest, _) = feature.intercept(request: request, additionalFirstPartyHosts: nil)

        // Then
        XCTAssertNil(modifiedRequest.value(forHTTPHeaderField: GraphQLHeaders.operationName), "GraphQL operation name header should be removed")
        XCTAssertNil(modifiedRequest.value(forHTTPHeaderField: GraphQLHeaders.operationType), "GraphQL operation type header should be removed")
        XCTAssertNil(modifiedRequest.value(forHTTPHeaderField: GraphQLHeaders.variables), "GraphQL variables header should be removed")
        XCTAssertNil(modifiedRequest.value(forHTTPHeaderField: GraphQLHeaders.payload), "GraphQL payload header should be removed")
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
                { feature.intercept(task: tasks.randomElement()!, with: [], additionalFirstPartyHosts: nil, trackingMode: .automatic) },
                { feature.task(tasks.randomElement()!, didReceive: .mockRandom()) },
                { feature.task(tasks.randomElement()!, didFinishCollecting: .mockAny()) },
                { feature.task(tasks.randomElement()!, didCompleteWithError: nil) },
                { try? feature.bind(configuration: .init(delegateClass: SessionDataDelegateMock.self)) },
                { feature.unbind(delegateClass: SessionDataDelegateMock.self) }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    // MARK: - NetworkContextCoreProvider Tests

    func testWhenReceivingContextMessage_itCreatesNetworkContextWithUserAndAccountInformation() throws {
        // Given
        let provider = NetworkContextCoreProvider()
        let userInfo = UserInfo(id: "user123", name: "TestUser", email: "test@example.com")
        let accountInfo = AccountInfo(id: "account456", name: "TestAccount")
        let rumContext: RUMCoreContext = .mockWith(applicationID: "app123", sessionID: .mockWith("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))

        let context = DatadogContext.mockWith(
            userInfo: userInfo,
            accountInfo: accountInfo,
            additionalContext: [rumContext]
        )

        // When
        let result = provider.receive(message: .context(context), from: core)

        // Then
        XCTAssertTrue(result)
        let networkContext = try XCTUnwrap(provider.currentNetworkContext)

        // Verify RUM context
        XCTAssertEqual(networkContext.rumContext?.applicationID, "app123")
        XCTAssertEqual(networkContext.rumContext?.sessionID, "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")

        // Verify User configuration context
        XCTAssertEqual(networkContext.userConfigurationContext?.id, "user123")
        XCTAssertEqual(networkContext.userConfigurationContext?.name, "TestUser")
        XCTAssertEqual(networkContext.userConfigurationContext?.email, "test@example.com")

        // Verify Account configuration context
        XCTAssertEqual(networkContext.accountConfigurationContext?.id, "account456")
        XCTAssertEqual(networkContext.accountConfigurationContext?.name, "TestAccount")
    }

    func testWhenReceivingContextMessage_withoutUserAndAccountInfo_itCreatesNetworkContextWithNilValues() throws {
        // Given
        let provider = NetworkContextCoreProvider()
        let rumContext: RUMCoreContext = .mockWith(applicationID: "app123", sessionID: .mockWith("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))

        let context = DatadogContext.mockWith(
            userInfo: .mockEmpty(),
            accountInfo: nil,
            additionalContext: [rumContext]
        )

        // When
        let result = provider.receive(message: .context(context), from: core)

        // Then
        XCTAssertTrue(result)
        let networkContext = try XCTUnwrap(provider.currentNetworkContext)

        // Verify RUM context is still available
        XCTAssertEqual(networkContext.rumContext?.applicationID, "app123")
        XCTAssertEqual(networkContext.rumContext?.sessionID, "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")

        // Verify User and Account configuration contexts are nil
        XCTAssertNil(networkContext.userConfigurationContext?.id)
        XCTAssertNil(networkContext.accountConfigurationContext)
    }

    func testWhenReceivingNonContextMessage_itReturnsFalse() {
        // Given
        let provider = NetworkContextCoreProvider()

        // When
        let result = provider.receive(message: .payload("some data"), from: core)

        // Then
        XCTAssertFalse(result)
        XCTAssertNil(provider.currentNetworkContext)
    }

    // MARK: - Subclass Delegate Handling

    func testGivenBothModesEnabled_whenUsingDelegateSubclass_itOnlyProcessesWithRegisteredDelegate() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Register BASE delegate class
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: DelegateBaseClass.self), in: core) // Registered Delegate mode

        let session = server.getInterceptedURLSession()

        // When - Use subclass delegate at runtime with a completion handler
        let subclassDelegate = DelegateSubClass()
        let url = URL.mockAny()
        let task = session.dataTask(with: url) { _, _, _ in }
        task.delegate = subclassDelegate
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

        let interception = try XCTUnwrap(handler.interception(for: url))

        // Should use registered delegate mode (because subclass delegate matches registered base class via isKind(of:))
        XCTAssertEqual(interception.trackingMode, .registeredDelegate, "Subclass delegate should be handled by registered delegate mode")
        XCTAssertNotNil(interception.metrics, "Should capture metrics")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data once (not duplicated, automatic capture is skipped)")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    class MockDelegate: NSObject, URLSessionDataDelegate {
    }

    class MockDelegate2: NSObject, URLSessionDataDelegate {
    }

    class DelegateBaseClass: NSObject, URLSessionDataDelegate {
    }

    class DelegateSubClass: DelegateBaseClass {
    }
}
