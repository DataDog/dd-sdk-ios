/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

let defaultHTTPHeaders: [String: String] = ["defaultKey": "defaultValue"]
let modifiedHTTPHeaders: [String: String] = ["key": "value"]
let secondModifiedHTTPHeaders: [String: String] = ["alt_key": "alt_value"]

class URLSessionSwizzlerTests: XCTestCase {
    /// URL.mockAny() is a valid URL so that it loads actual resource and exceeds expectation timeouts
    let mockURL = URL(string: "https://foo.bar")!
    let mockURLRequest: URLRequest = {
        var req = URLRequest(url: URL(string: "https://foo.bar")!)
        req.allHTTPHeaderFields = defaultHTTPHeaders
        return req
    }()

    var session: URLSession { URLSession.shared }
    // swiftlint:disable implicitly_unwrapped_optional
    var resumeSwizzler: URLSessionSwizzler.Resume!
    var firstSwizzler: URLSessionSwizzler!
    var secondSwizzler: URLSessionSwizzler!
    var thirdSwizzler: URLSessionSwizzler!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        resumeSwizzler = URLSessionSwizzler.Resume()
        firstSwizzler = try! URLSessionSwizzler(with: self.resumeSwizzler)
        secondSwizzler = try! URLSessionSwizzler(with: self.resumeSwizzler)
        thirdSwizzler = try! URLSessionSwizzler(with: self.resumeSwizzler)
    }

    override func tearDown() {
        super.tearDown()
        firstSwizzler.unswizzle()
        resumeSwizzler.unswizzle()
    }

    func test_dataTask_urlCompletion() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        // intercepts and injects modifiedHTTPHeaders
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders, id: 1)
        // does NOT intercept
        let secondInterceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: nil, id: 2)
        // intercepts and injects secondModifiedHTTPHeaders
        let thirdInterceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: secondModifiedHTTPHeaders, id: 3)

        firstSwizzler.swizzle(using: interceptorTuple.block)
        secondSwizzler.swizzle(using: secondInterceptorTuple.block)
        thirdSwizzler.swizzle(using: thirdInterceptorTuple.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        XCTAssertEqual(taskRequest.url, mockURL)
        if #available(iOS 13.0, *) {
            XCTAssertNil(taskRequest.allHTTPHeaderFields)
        } else {
            XCTAssertEqual(taskRequest.allHTTPHeaderFields, modifiedHTTPHeaders + secondModifiedHTTPHeaders)
        }

        wait(
            for: [
                thirdInterceptorTuple.interceptionExpectation,
                secondInterceptorTuple.interceptionExpectation,
                interceptorTuple.interceptionExpectation
            ],
            timeout: 1,
            enforceOrder: true
        )

        task.resume()

        /// we expect secondInterceptor not to observe as it does not intercept in the first place
        let resumeExpectations: [XCTestExpectation] = [
            interceptorTuple.observationStartingExpectation,
            thirdInterceptorTuple.observationStartingExpectation,
            completionExpectation,
            thirdInterceptorTuple.observationCompletedExpectation,
            interceptorTuple.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: 1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders, id: 1)
        let secondInterceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: nil, id: 2)
        let thirdInterceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: secondModifiedHTTPHeaders, id: 3)

        firstSwizzler.swizzle(using: interceptorTuple.block)
        secondSwizzler.swizzle(using: secondInterceptorTuple.block)
        thirdSwizzler.swizzle(using: thirdInterceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        XCTAssertEqual(taskRequest.url, mockURL)
        let expectedHeaders = defaultHTTPHeaders + modifiedHTTPHeaders + secondModifiedHTTPHeaders
        XCTAssertEqual(taskRequest.allHTTPHeaderFields, expectedHeaders)

        wait(
            for: [
                thirdInterceptorTuple.interceptionExpectation,
                secondInterceptorTuple.interceptionExpectation,
                interceptorTuple.interceptionExpectation
            ],
            timeout: 1,
            enforceOrder: true
        )

        task.resume()

        let resumeExpectations: [XCTestExpectation] = [
            interceptorTuple.observationStartingExpectation,
            thirdInterceptorTuple.observationStartingExpectation,
            completionExpectation,
            thirdInterceptorTuple.observationCompletedExpectation,
            interceptorTuple.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: 1,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion_alreadyTracedRequest() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders, id: 1)
        let secondInterceptorTuple = buildInterceptorTuple(modifiedHTTPHeaders: modifiedHTTPHeaders, id: 2)
        /// secondInterception injects headers
        /// when first interceptor provides the same headers, interception should be ignored by URLSessionSwizzler
        interceptorTuple.observationStartingExpectation.isInverted = true
        interceptorTuple.observationCompletedExpectation.isInverted = true

        firstSwizzler.swizzle(using: interceptorTuple.block)
        secondSwizzler.swizzle(using: secondInterceptorTuple.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        XCTAssertEqual(taskRequest.url, mockURL)
        let expectedHeaders = defaultHTTPHeaders + modifiedHTTPHeaders
        XCTAssertEqual(taskRequest.allHTTPHeaderFields, expectedHeaders)

        wait(
            for: [
                secondInterceptorTuple.interceptionExpectation,
                interceptorTuple.interceptionExpectation
            ],
            timeout: 1,
            enforceOrder: true
        )

        task.resume()

        /// we expect firstInterceptor not to observe as the request was already traced at its firstInterceptor
        let resumeExpectations: [XCTestExpectation] = [
            secondInterceptorTuple.observationStartingExpectation,
            completionExpectation,
            secondInterceptorTuple.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
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

private extension Dictionary where Key == String, Value == String {
    static func + (lhs: Self, rhs: Self) -> Self {
        return lhs.merging(rhs) { lhsKey, _ in return lhsKey }
    }
}
extension URLSessionSwizzler {
    func unswizzle() {
        dataTaskWithURL.unswizzle()
        dataTaskwithRequest.unswizzle()
        Self.resume.unswizzle()
    }
}
private typealias InterceptorTuple = (
    block: RequestInterceptor,
    interceptionExpectation: XCTestExpectation,
    observationStartingExpectation: XCTestExpectation,
    observationCompletedExpectation: XCTestExpectation
)
private func buildInterceptorTuple(modifiedHTTPHeaders: [String: String]?, id: Int) -> InterceptorTuple {
    let interceptionExpectation = XCTestExpectation(description: "\(id): interceptionExpectation")
    let observationExpectation_start = XCTestExpectation(description: "\(id): observationExpectation.start")
    let observationExpectation_completed = XCTestExpectation(description: "\(id): observationExpectation.completed")
    if modifiedHTTPHeaders == nil {
        observationExpectation_start.isInverted = true
        observationExpectation_completed.isInverted = true
    }
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
        return InterceptionResult(taskObserver: observer, httpHeaders: httpHeaders)
    }
    return (
        block: interceptor,
        interceptionExpectation: interceptionExpectation,
        observationStartingExpectation: observationExpectation_start,
        observationCompletedExpectation: observationExpectation_completed
    )
}
