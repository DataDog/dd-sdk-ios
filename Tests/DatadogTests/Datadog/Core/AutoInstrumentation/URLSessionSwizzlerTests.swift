/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionSwizzlerTests: XCTestCase {
    /// URL.mockAny() is a valid URL so that it loads actual resource and exceeds expectation timeouts
    /// We use unsupported URLs so that the task goes through its URLProtocol chain and **immediately** returns with "unsupported URL" error
    let mockURL = URL(string: "foo://example.com")!
    let mockURLRequest = URLRequest(url: URL(string: "foo://example.com")!)
    let modifiedURLRequest = URLRequest(url: URL(string: "bar://example.com")!)
    let secondModifiedURLRequest = URLRequest(url: URL(string: "bar://foo.example.com")!)

    let timeout = 1.0

    var session: URLSession { URLSession.shared }
    // swiftlint:disable implicitly_unwrapped_optional
    var firstSwizzler: URLSessionSwizzler!
    var secondSwizzler: URLSessionSwizzler!
    var thirdSwizzler: URLSessionSwizzler!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        firstSwizzler = try! URLSessionSwizzler()
        secondSwizzler = try! URLSessionSwizzler()
        thirdSwizzler = try! URLSessionSwizzler()
    }

    override func tearDown() {
        super.tearDown()
        firstSwizzler.unswizzle()
    }

    func test_dataTask_urlCompletion() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        // intercepts and injects modifiedHTTPHeaders
        let mock1 = MockInterceptor(id: 1, modifiedRequest: modifiedURLRequest)
        // does NOT intercept
        let mock2 = MockInterceptor(id: 2, modifiedRequest: nil)
        // intercepts and injects secondModifiedHTTPHeaders
        let mock3 = MockInterceptor(id: 3, modifiedRequest: secondModifiedURLRequest)

        firstSwizzler.swizzle(using: mock1.block)
        secondSwizzler.swizzle(using: mock2.block)
        thirdSwizzler.swizzle(using: mock3.block)

        let task = session.dataTask(with: mockURL) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        if #available(iOS 13.0, *) {
            XCTAssertEqual(taskRequest.url, mockURL)
        } else {
            XCTAssertEqual(taskRequest.url, modifiedURLRequest.url)
        }

        wait(
            for: [
                mock1.interceptionExpectation,
                mock2.interceptionExpectation,
                mock3.interceptionExpectation
            ],
            timeout: timeout
        )

        task.resume()

        /// we expect secondInterceptor not to observe as it does not intercept in the first place
        let resumeExpectations: [XCTestExpectation] = [
            mock1.observationStartingExpectation,
            mock3.observationStartingExpectation,
            completionExpectation,
            mock3.observationCompletedExpectation,
            mock1.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: timeout,
            enforceOrder: true
        )
    }

    func test_dataTask_requestCompletion() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let mock1 = MockInterceptor(id: 1, modifiedRequest: modifiedURLRequest)
        let mock2 = MockInterceptor(id: 2, modifiedRequest: nil)
        let mock3 = MockInterceptor(id: 3, modifiedRequest: secondModifiedURLRequest)

        firstSwizzler.swizzle(using: mock1.block)
        secondSwizzler.swizzle(using: mock2.block)
        thirdSwizzler.swizzle(using: mock3.block)

        let task = session.dataTask(with: mockURLRequest) { _, _, _ in
            completionExpectation.fulfill()
        }

        let taskRequest = task.originalRequest!
        XCTAssertEqual(taskRequest, modifiedURLRequest)

        wait(
            for: [
                mock1.interceptionExpectation,
                mock2.interceptionExpectation,
                mock3.interceptionExpectation
            ],
            timeout: timeout
        )

        task.resume()

        let resumeExpectations: [XCTestExpectation] = [
            mock1.observationStartingExpectation,
            mock3.observationStartingExpectation,
            completionExpectation,
            mock3.observationCompletedExpectation,
            mock1.observationCompletedExpectation
        ]
        wait(
            for: resumeExpectations,
            timeout: timeout,
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

extension URLSessionSwizzler {
    func unswizzle() {
        dataTaskWithURL.unswizzle()
        dataTaskwithRequest.unswizzle()
        Self.resume.unswizzle()
        Self.resume = URLSessionSwizzler.Resume()
    }
}

private class MockInterceptor {
    let block: RequestInterceptor
    let interceptionExpectation: XCTestExpectation
    let observationStartingExpectation: XCTestExpectation
    let observationCompletedExpectation: XCTestExpectation

    init(id: Int, modifiedRequest: URLRequest?) {
        let interceptionExpectation = XCTestExpectation(description: "\(id): interceptionExpectation")
        let observationStartingExpectation = XCTestExpectation(description: "\(id): observationExpectation.start")
        let observationCompletedExpectation = XCTestExpectation(description: "\(id): observationExpectation.completed")

        if modifiedRequest == nil {
            observationStartingExpectation.isInverted = true
            observationCompletedExpectation.isInverted = true
        }
        let observer: TaskObserver = { event in
            switch event {
            case .starting:
                observationStartingExpectation.fulfill()
            case .completed:
                observationCompletedExpectation.fulfill()
            }
        }
        let interceptor: RequestInterceptor = { originalRequest in
            interceptionExpectation.fulfill()
            if let someRequest = modifiedRequest {
                return InterceptionResult(modifiedRequest: someRequest, taskObserver: observer)
            } else {
                return nil
            }
        }
        self.interceptionExpectation = interceptionExpectation
        self.observationStartingExpectation = observationStartingExpectation
        self.observationCompletedExpectation = observationCompletedExpectation
        self.block = interceptor
    }
}
