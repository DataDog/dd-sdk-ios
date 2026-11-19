/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class URLSessionSwizzlerTests: XCTestCase {
    func testSwizzling_dataTaskWithCompletion() throws {
        let didReceive = expectation(description: "didReceive")
        didReceive.expectedFulfillmentCount = 2

        let didInterceptCompletion = expectation(description: "interceptCompletion")
        didInterceptCompletion.expectedFulfillmentCount = 2

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptCompletionHandler: { _, _, _ in
                didInterceptCompletion.fulfill()
            }, didReceive: { _, _ in
                didReceive.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let url = URL(string: "https://www.datadoghq.com/")!
        session.dataTask(with: url) { _, _, _ in }.resume() // intercepted
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in }.resume() // intercepted

        swizzler.unswizzle()
        session.dataTask(with: url) { _, _, _ in }.resume() // not intercepted
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in }.resume() // not intercepted

        wait(for: [didReceive, didInterceptCompletion], timeout: 5)
    }

    @available(iOS 15, tvOS 15, *)
    func testSwizzling_asyncDataAPIs_interceptCompletionAndCallOriginalOnce() async throws {
        let body: Data = .mock(ofSize: 10)
        var receivedData: [Data] = []
        var interceptedData: [Data?] = []

        let swizzler = URLSessionSwizzler()
        try swizzler.swizzle(
            interceptCompletionHandler: { _, data, _ in interceptedData.append(data) },
            didReceive: { _, data in receivedData.append(data) }
        )
        defer { swizzler.unswizzle() }

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: body), skipIsMainThreadCheck: true)
        let session = server.getInterceptedURLSession()

        let (data1, response1) = try await session.data(from: URL.mockAny())
        let (data2, response2) = try await session.data(for: URLRequest(url: URL.mockAny()))
        _ = server.waitAndReturnRequests(count: 2)

        // original completion delivered unchanged values, exactly once per call (async API would trap otherwise)
        XCTAssertEqual(data1, body)
        XCTAssertEqual(data2, body)
        XCTAssertEqual((response1 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response2 as? HTTPURLResponse)?.statusCode, 200)
        // intercepted once per request
        XCTAssertEqual(receivedData, [body, body])
        XCTAssertEqual(interceptedData, [body, body])
    }

    // MARK: - AsyncDataTaskCompletionHandler guards

    func testAsyncDataTaskHook_whenSelectorIsMissing_itIsNotBuilt() {
        XCTAssertNil(URLSessionSwizzler.AsyncDataTaskCompletionHandler.build(selectorName: "_ddtest_missing:delegate:completionHandler:"))
    }

    func testAsyncDataTaskHook_whenSignatureIsIncompatible_itIsNotBuilt() {
        XCTAssertNil(
            URLSessionSwizzler.AsyncDataTaskCompletionHandler.build(
                selectorName: "ddtest_incompatible:delegate:completionHandler:",
                klass: AsyncDataTaskSessionMock.self
            )
        )
    }

    func testAsyncDataTaskHook_whenCompletionIsNil_itPassesItThrough() throws {
        let hook = try XCTUnwrap(
            URLSessionSwizzler.AsyncDataTaskCompletionHandler.build(
                selectorName: "ddtest_dataTaskWith:delegate:completionHandler:",
                klass: AsyncDataTaskSessionMock.self
            )
        )
        var intercepted = 0
        hook.swizzle(interceptCompletion: { _, _, _ in intercepted += 1 }, didReceive: { _, _ in intercepted += 1 })
        defer { hook.unswizzle() }

        let session = AsyncDataTaskSessionMock()
        _ = session.dataTask(with: URL.mockAny() as NSURL, delegate: nil, completionHandler: nil)

        XCTAssertEqual(session.callCount, 1)
        XCTAssertNil(session.receivedCompletion, "nil completion must reach the original implementation as nil")
        XCTAssertEqual(intercepted, 0)
    }

    func testAsyncDataTaskHook_whenCompletionIsGiven_itInterceptsAndCallsOriginalOnce() throws {
        let hook = try XCTUnwrap(
            URLSessionSwizzler.AsyncDataTaskCompletionHandler.build(
                selectorName: "ddtest_dataTaskWith:delegate:completionHandler:",
                klass: AsyncDataTaskSessionMock.self
            )
        )
        let body: Data = .mock(ofSize: 10)
        var received: [Data] = []
        var intercepted: [Data?] = []
        hook.swizzle(interceptCompletion: { _, data, _ in intercepted.append(data) }, didReceive: { _, data in received.append(data) })
        defer { hook.unswizzle() }

        let session = AsyncDataTaskSessionMock()
        var calls: [Data?] = []
        let task = session.dataTask(with: URL.mockAny() as NSURL, delegate: nil) { data, _, _ in calls.append(data) }
        session.complete(with: body)

        XCTAssertEqual(calls, [body])
        XCTAssertEqual(received, [body])
        XCTAssertEqual(intercepted, [body])
        XCTAssertTrue(task.dd.hasCompletion)
    }
}

/// Exposes selectors shaped like the private `NSURLSession` async-data entry points.
private final class AsyncDataTaskSessionMock: NSObject {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    private(set) var callCount = 0
    private(set) var receivedCompletion: CompletionHandler?
    private let task = URLSession.shared.dataTask(with: URL(string: "https://www.datadoghq.com/")!)

    @objc(ddtest_dataTaskWith:delegate:completionHandler:)
    dynamic func dataTask(with urlOrRequest: AnyObject, delegate: AnyObject?, completionHandler: CompletionHandler?) -> URLSessionDataTask {
        callCount += 1
        receivedCompletion = completionHandler
        return task
    }

    @objc(ddtest_incompatible:delegate:completionHandler:)
    func incompatible(_ value: Int, delegate: AnyObject?, completionHandler: CompletionHandler?) -> URLSessionDataTask {
        return task
    }

    func complete(with data: Data) {
        receivedCompletion?(data, nil, nil)
    }
}
