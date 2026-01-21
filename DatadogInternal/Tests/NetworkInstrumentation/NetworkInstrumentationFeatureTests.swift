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
        core = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    /// Sets up a test with interception expectations for single-request scenarios.
    /// Returns server, start expectation, and complete expectation.
    private func setupInterceptionTest(
        dataSize: Int = 10,
        statusCode: Int = 200,
        skipIsMainThreadCheck: Bool = false
    ) -> (ServerMock, XCTestExpectation, XCTestExpectation) {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: statusCode), data: .mock(ofSize: dataSize)),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        return (server, notifyInterceptionDidStart, notifyInterceptionDidComplete)
    }

    // MARK: - Metrics Mode

    func testMetricsMode_capturesMetricsForDataTaskWithURL() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given
        // Automatic mode (required)
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Metrics mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testMetricsMode_capturesMetricsForDataTaskWithURLRequest() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.onRequestMutation = { _, _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given
        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Metrics mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testMetricsMode_capturesMetricsForUploadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Metrics mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    func testMetricsMode_capturesMetricsForDownloadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Download task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data not captured for download tasks (saved to file)")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
        XCTAssertNotNil(interception.startDate, "Should capture approximate start date")
        XCTAssertNotNil(interception.endDate, "Should capture approximate end date")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncDataFromURL() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncDataWithSessionDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncDataWithPerTaskDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncUploadWithPerTaskDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Data is not captured when using Async API")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncUploadWithSessionDelegate() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForAsyncDataTaskWithURLRequest() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }
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

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )

        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Async APIs return data directly to caller, bypassing delegate's didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testMetricsMode_capturesMetricsForCombineDataTask() throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Metrics mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testMetricsMode_capturesMetricsForCompletionHandlerDataTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Metrics mode should capture data")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    func testMetricsMode_capturesMetricsForCompletionHandlerUploadTask() throws {
        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest(skipIsMainThreadCheck: true)

        // Given
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        // Metrics mode
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with session using registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertNil(interception.data, "Upload tasks with completion handler don't capture data via delegate")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
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

    @available(iOS 13.0, *)
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

    @available(iOS 13.0, tvOS 13.0, *)
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

    @available(iOS 13.0, *)
    func testAutomaticMode_tracksAsyncUploadTasks() async throws {
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }

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

        // Session has a delegate, but it's not registered for metrics mode
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
        // pre iOS 15 cannot set delegate per task
        guard #available(iOS 15, tvOS 15, *) else {
            return
        }

        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        // Given - Enable both automatic and metrics modes (reflects real-world usage)
        let delegate1 = MockDelegate()
        let delegate2 = MockDelegate2()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: MockDelegate.self), in: core) // Metrics mode

        let session = server.getInterceptedURLSession()

        // When
        let url1 = URL.mockWith(url: "https://www.foo.com/1")
        let task1 = session.dataTask(with: url1) // intercepted by metrics mode
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
        XCTAssertEqual(interception1.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception1.metrics, "Should capture metrics in metrics mode")
        XCTAssertEqual(interception1.data?.count, 10, "Should capture data in metrics mode")

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

        // Given - Enable both automatic and metrics modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core) // Metrics

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
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception.metrics, "Metrics mode should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Data size should match expected size")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 15, tvOS 15, *)
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Should use metrics mode")
        XCTAssertNotNil(interception.metrics, "Should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via completion handler")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 15, tvOS 15, *)
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
        XCTAssertEqual(interception.trackingMode, .metrics, "Should use metrics mode")
        XCTAssertNotNil(interception.metrics, "Should capture URLSessionTaskMetrics")
        XCTAssertEqual(interception.data?.count, 10, "Should capture data via delegate didReceive")
        XCTAssertEqual(interception.responseSize, 10, "Should capture response size")
        XCTAssertNotNil(interception.completion, "Should capture completion")
    }

    @available(iOS 15, tvOS 15, *)
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

    @available(iOS 15, tvOS 15, *)
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

    @available(iOS 15, tvOS 15, *)
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

    @available(iOS 15, tvOS 15, *)
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

    func testGivenBothModesEnabled_whenUsingAsyncAPI_itCapturesAllValues() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidStart.expectedFulfillmentCount = 2
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        // Given - Enable both modes
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        let session = server.getInterceptedURLSession() // No session-level delegate

        // When - Using Async/await API
        let url1: URL = .mockRandom()
        _ = try? await session.data(from: url1, delegate: delegate) // Metrics mode (explicit delegate)
        let url2: URL = .mockRandom()
        _ = try? await session.data(from: url2) // Automatic mode (no delegate at all)

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
        XCTAssertEqual(interception1.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
        XCTAssertNotNil(interception1.metrics, "Task in metrics mode should collect metrics")
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
        // pre iOS 15 cannot set delegate per task
        guard #available(iOS 15, tvOS 15, *) else {
            return
        }

        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
        notifyInterceptionDidComplete.expectedFulfillmentCount = 2
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )

        // Given - Both modes enabled
        let delegate = SessionDataDelegateMock()
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: SessionDataDelegateMock.self), in: core) // Metrics mode

        let session = server.getInterceptedURLSession()

        // When - Download task with per-task delegate (metrics mode)
        let url1 = URL.mockWith(url: "https://www.foo.com/download1")
        let task1 = session.downloadTask(with: url1)
        task1.delegate = delegate
        task1.resume()

        // Download task without delegate (automatic mode)
        let url2 = URL.mockWith(url: "https://www.foo.com/download2")
        let task2 = session.downloadTask(with: url2)
        task2.resume()

        // Then
        wait(for: [notifyInterceptionDidComplete], timeout: 5)
        _ = server.waitAndReturnRequests(count: 2)

        // Verify task with delegate uses metrics mode
        let interception1 = try XCTUnwrap(handler.interception(for: url1))
        XCTAssertEqual(interception1.trackingMode, .metrics, "Download task with registered per-task delegate should use metrics mode")
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
        let url = URL(string: "https://192.0.2.1:9999")! // TEST-NET-1: Reserved for documentation, never responds
        let task = session.dataTask(with: url)
        task.resume()
        Thread.sleep(forTimeInterval: 0.05) // Brief delay to ensure task has started
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

    func testGivenMetricsMode_whenTaskCompletesWithFailure_itCapturesError() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")

        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

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

        // Metrics mode captures metrics and completion (even on failure)
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")

        let metrics = try XCTUnwrap(interception.metrics, "Should capture metrics even on failure")
        XCTAssertGreaterThan(metrics.fetch.start, dateBeforeRequest)
        XCTAssertLessThan(metrics.fetch.end, dateAfterRequest)

        // Data is NOT captured without completion handler
        XCTAssertNil(interception.data, "Data not captured without completion handler")

        // Error is captured via setState
        let completion = try XCTUnwrap(interception.completion, "Should capture completion")
        XCTAssertEqual((completion.error as? NSError)?.localizedDescription, "some error")
    }

    func testGivenMetricsMode_whenTaskCompletesWithSuccess_itCapturesAllValues() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mockRandom()))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

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

        // Metrics mode captures metrics and completion
        XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")

        let metrics = try XCTUnwrap(interception.metrics, "Should capture metrics")
        XCTAssertGreaterThan(metrics.fetch.start, dateBeforeRequest)
        XCTAssertLessThan(metrics.fetch.end, dateAfterRequest)

        // Data is captured in metrics mode via didReceive delegate swizzling
        XCTAssertNotNil(interception.data, "Data should be captured in metrics mode via didReceive swizzling")
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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: randomData))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

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
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")

        let testError = NSError(domain: "test", code: 123, userInfo: nil)
        let server = ServerMock(delivery: .failure(error: testError))

        handler.onInterceptionDidStart = { _ in notifyInterceptionDidStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in notifyInterceptionDidComplete.fulfill() }

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

    @available(iOS 13.0, tvOS 13.0, *)
    func testGivenMetricsMode_whenUsingAsyncAPI_itCapturesAllValues() async throws {
        /// Testing only 16.0 or above because 15.0 has ThreadSanitizer issues with async APIs
        guard #available(iOS 16, tvOS 16, *) else {
            return
        }
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let notifyInterceptionDidComplete = expectation(description: "Notify interception did complete")
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
            XCTAssertEqual(interception.trackingMode, .metrics, "Task with registered delegate should be in metrics mode")
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

    func testWhenEnableMetricsModeOnTheSameDelegate_thenItPrintsAWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Then
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            The delegate class SessionDataDelegateMock is already instrumented.
            The previous instrumentation will be disabled in favor of the new one.
            """
        )
    }

    func testWhenEnableMetricsModeBeforeAutomaticMode_thenItPrintsAnError() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When - Try to enable metrics mode without enabling automatic mode first
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: SessionDataDelegateMock.self), in: core)

        // Then
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            Metrics mode requires automatic network instrumentation to be enabled first.
            Please enable RUM or Trace with `urlSessionTracking` parameter before enabling metrics mode.
            """
        )
    }

    // MARK: - Filtering Out Intake Requests

    func testAutomaticMode_doesNotTrackSDKRequests() throws {
        // Given - Enable automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)

        // Create a real URLSession
        let session = URLSession(configuration: .ephemeral)

        // Track if any requests with DD-REQUEST-ID are intercepted
        var interceptedSDKRequests: [URLSessionTaskInterception] = []
        handler.onInterceptionDidStart = { interception in
            interceptedSDKRequests.append(interception)
        }

        // When - Make a request to a custom endpoint with DD-REQUEST-ID header (simulating SDK internal request)
        let customEndpointURL = URL(string: "http://custom-endpoint.example.com/api/v2/intake")!
        var request = URLRequest(url: customEndpointURL)
        request.setValue(UUID().uuidString, forHTTPHeaderField: "DD-REQUEST-ID")

        let taskCompleted = expectation(description: "Task completed")
        let task = session.dataTask(with: request) { _, _, _ in
            taskCompleted.fulfill()
        }
        task.resume()

        // Wait for task to complete
        wait(for: [taskCompleted], timeout: 10)

        // Then - Verify SDK request with DD-REQUEST-ID was not intercepted
        XCTAssertEqual(interceptedSDKRequests.count, 0, "Should not intercept SDK requests with DD-REQUEST-ID header, even to custom endpoints")
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
        feature.intercept(task: .mockAny(), with: traceContexts, additionalFirstPartyHosts: nil, trackingMode: .mockRandom())
        feature.flush()

        // Then
        let interception = try XCTUnwrap(handler.interceptions.first?.value)
        XCTAssertEqual(interception.trace, traceContexts.first, "It should register first injected Trace Context")
    }

    // MARK: - First Party Hosts

    func testAutomaticMode_detectsFirstPartyHosts() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

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

    func testMetricsMode_detectsFirstPartyHosts() throws {
        let notifyInterceptionDidStart = expectation(description: "Notify interception did start")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

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
        waitForExpectations(timeout: 5, handler: nil)
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
        let rumContext = RUMCoreContext(applicationID: "app123", sessionID: "session789")

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
        XCTAssertEqual(networkContext.rumContext?.sessionID, "session789")

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
        let rumContext = RUMCoreContext(applicationID: "app123", sessionID: "session789")

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
        XCTAssertEqual(networkContext.rumContext?.sessionID, "session789")

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

    func testGivenBothModesEnabled_whenUsingDelegateSubclass_itOnlyProcessesInMetricsMode() throws {
        // pre iOS 15 cannot set delegate per task
        guard #available(iOS 15, tvOS 15, *) else {
            return
        }

        let (server, notifyInterceptionDidStart, notifyInterceptionDidComplete) = setupInterceptionTest()

        // Given - Register BASE delegate class for metrics mode
        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core) // Automatic mode
        try URLSessionInstrumentation.enableOrThrow(with: .init(delegateClass: DelegateBaseClass.self), in: core) // Metrics mode

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

        // Should use metrics mode (because subclass delegate matches registered base class via isKind(of:))
        XCTAssertEqual(interception.trackingMode, .metrics, "Subclass delegate should be handled by metrics mode")
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
