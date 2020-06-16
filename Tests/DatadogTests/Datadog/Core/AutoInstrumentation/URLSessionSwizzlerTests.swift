/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionSwizzlerTests: XCTestCase {
    /// URL.mockAny() is a valid URL so that it loads actual resource and exceeds expectation timeouts
    let mockURL = URL(string: "https://foo.bar")!
    let mockURLRequest: URLRequest = {
        var req = URLRequest(url: URL(string: "https://foo.bar")!)
        req.allHTTPHeaderFields = ["defaultKey": "defaultValue"]
        return req
    }()
    let modifiedHTTPHeaders: [String: String] = ["key": "value"]
    let mergedHTTPHeaders: [String: String] = ["key": "value", "defaultKey": "defaultValue"]

    var session: URLSession { URLSession.shared }
    var swizzler = try! URLSessionSwizzler()

    override func tearDown() {
        super.tearDown()
        swizzler.unswizzle()
        URLSessionSwizzler.hasSwizzledBefore = false
    }

    func test_swizzleOnce_calledMultipleTimes() {
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: nil)
        // first swizzling ✅
        XCTAssertTrue(swizzler.swizzleOnce(using: interceptorTuple.block))
        // further swizzling attempts ❌
        XCTAssertFalse(swizzler.swizzleOnce(using: interceptorTuple.block))
        XCTAssertFalse(swizzler.swizzleOnce(using: interceptorTuple.block))
    }

    func test_dataTask_urlCompletion_alwaysIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        XCTAssertEqual(taskRequest.url, mockURL)
        XCTAssertNil(taskRequest.allHTTPHeaderFields)

        wait(
            for: [interceptorTuple.interceptionExpectation],
            timeout: 1,
            enforceOrder: true
        )

        task.resume()

        let resumeExpectations: [XCTestExpectation] = [
            interceptorTuple.observationStartingExpectation,
            completionExpectation,
            interceptorTuple.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: 1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_alwaysIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }

        XCTAssertEqual(task.originalRequest?.url, mockURLRequest.url)
        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, mergedHTTPHeaders)

        wait(
            for: [interceptorTuple.interceptionExpectation],
            timeout: 1,
            enforceOrder: true
        )

        task.resume()

        let resumeExpectations: [XCTestExpectation] = [
            interceptorTuple.observationStartingExpectation,
            completionExpectation,
            interceptorTuple.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: 1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_alwaysIntercept_noResume() {
        let interceptor: RequestInterceptor = { _ in
            let observer: TaskObserver = { event in
                XCTFail("Observer should not be called without resume()")
            }
            return (taskObserver: observer, httpHeaders: self.modifiedHTTPHeaders)
        }

        swizzler.swizzleOnce(using: interceptor)

        session.dataTask(with: mockURLRequest) { _, _, _ in }
    }

    func test_dataTask_urlCompletion_neverIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: nil)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }
        task.resume()

        XCTAssertEqual(task.originalRequest?.url, mockURL)

        wait(
            for: [interceptorTuple.interceptionExpectation, completionExpectation],
            timeout: 1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_neverIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: nil)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }
        task.resume()

        XCTAssertEqual(task.originalRequest?.url, mockURL)

        wait(
            for: [interceptorTuple.interceptionExpectation, completionExpectation],
            timeout: 1,
            enforceOrder: true
        )
    }
}

class URLSessionSwizzlerTests_DefaultConfig: URLSessionSwizzlerTests {
    private let _session = URLSession(configuration: .default)
    override var session: URLSession { _session }
}

class URLSessionSwizzlerTests_CustomDelegate: URLSessionSwizzlerTests {
    private class SessionDelegate: NSObject, URLSessionDelegate { }
    private let _session = URLSession(configuration: .default, delegate: SessionDelegate(), delegateQueue: OperationQueue())
    override var session: URLSession { _session }
}

private extension URLSessionSwizzler {
    func unswizzle() {
        dataTaskWithURL.unswizzle()
        dataTaskwithRequest.unswizzle()
        resume.unswizzle()
    }
}
private typealias InterceptorTuple = (
    block: RequestInterceptor,
    interceptionExpectation: XCTestExpectation,
    observationStartingExpectation: XCTestExpectation,
    observationCompletedExpectation: XCTestExpectation
)
private func buildInterceptorTuple(modifiedHTTPHeaders: [String: String]?) -> InterceptorTuple {
    let interceptionExpectation = XCTestExpectation(description: "interceptionExpectation")
    let observationExpectation_start = XCTestExpectation(description: "observationExpectation.start")
    let observationExpectation_completed = XCTestExpectation(description: "observationExpectation.completed")
    let observer: TaskObserver = { event in
        switch event {
        case .starting:
            observationExpectation_start.fulfill()
        case .completed:
            observationExpectation_completed.fulfill()
        }
    }
    let interceptor: RequestInterceptor = { originalRequest in
        interceptionExpectation.fulfill()
        guard let httpHeaders = modifiedHTTPHeaders else {
            return nil
        }
        return (taskObserver: observer, httpHeaders: httpHeaders)
    }
    return (
        block: interceptor,
        interceptionExpectation: interceptionExpectation,
        observationStartingExpectation: observationExpectation_start,
        observationCompletedExpectation: observationExpectation_completed
    )
}
