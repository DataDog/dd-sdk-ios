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
    let mockURLRequest = URLRequest(url: URL(string: "https://foo.bar")!)
    let modifiedURL = URL(string: "https://foo.bar.modified")!

    var session: URLSession { URLSession.shared }
    var swizzler = try! URLSessionSwizzler()

    override func tearDown() {
        super.tearDown()
        swizzler.unswizzle()
        URLSessionSwizzler.hasSwizzledBefore = false
    }

    func test_swizzleOnce_calledMultipleTimes() {
        let interceptorTuple = buildInterceptorTuple(modifiedURL: nil)
        // first swizzling ✅
        XCTAssertTrue(swizzler.swizzleOnce(using: interceptorTuple.block))
        // further swizzling attempts ❌
        XCTAssertFalse(swizzler.swizzleOnce(using: interceptorTuple.block))
        XCTAssertFalse(swizzler.swizzleOnce(using: interceptorTuple.block))
    }

    func test_dataTask_urlCompletion_alwaysIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedURL: modifiedURL)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }

        XCTAssertNotEqual(task.originalRequest?.url, mockURL)
        XCTAssertEqual(task.originalRequest?.url, modifiedURL)

        wait(
            for: [interceptorTuple.interceptionExpectation],
            timeout: 0.1,
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
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_alwaysIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedURL: modifiedURL)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }

        XCTAssertNotEqual(task.originalRequest?.url, mockURL)
        XCTAssertEqual(task.originalRequest?.url, modifiedURL)

        wait(
            for: [interceptorTuple.interceptionExpectation],
            timeout: 0.1,
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
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_alwaysIntercept_noResume() {
        let modifiedURL = URL(string: "https://foo.bar.modified")!
        let interceptor: RequestInterceptor = { originalRequest in
            var modifiedReq = originalRequest
            modifiedReq.url = modifiedURL

            let observer: TaskObserver = { event in
                XCTFail("Observer should not be called without resume()")
            }
            return (modifiedRequest: modifiedReq, taskObserver: observer)
        }

        swizzler.swizzleOnce(using: interceptor)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in }

        XCTAssertEqual(task.originalRequest?.url, modifiedURL)
    }

    func test_dataTask_urlCompletion_neverIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedURL: nil)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }
        task.resume()

        XCTAssertEqual(task.originalRequest?.url, mockURL)

        wait(
            for: [interceptorTuple.interceptionExpectation, completionExpectation],
            timeout: 0.1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_neverIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedURL: nil)

        swizzler.swizzleOnce(using: interceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }
        task.resume()

        XCTAssertEqual(task.originalRequest?.url, mockURL)

        wait(
            for: [interceptorTuple.interceptionExpectation, completionExpectation],
            timeout: 0.1,
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
private func buildInterceptorTuple(modifiedURL: URL?) -> InterceptorTuple {
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
        guard let someURL = modifiedURL else {
            return nil
        }
        var modifiedRequest = originalRequest
        modifiedRequest.url = someURL
        return (modifiedRequest: modifiedRequest, taskObserver: observer)
    }
    return (
        block: interceptor,
        interceptionExpectation: interceptionExpectation,
        observationStartingExpectation: observationExpectation_start,
        observationCompletedExpectation: observationExpectation_completed
    )
}
