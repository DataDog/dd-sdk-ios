/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private typealias Swizzler = URLSessionSwizzler

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

class URLSessionSwizzlerTests_DefaultConfig: URLSessionSwizzlerTests {
    private let _session = URLSession(configuration: .default)
    override var session: URLSession { _session }
}

class URLSessionSwizzlerTests_CustomDelegate: URLSessionSwizzlerTests {
    private class SessionDelegate: NSObject, URLSessionDelegate { }
    private let _session = URLSession(
        configuration: .default,
        delegate: SessionDelegate(),
        delegateQueue: OperationQueue()
    )
    override var session: URLSession { _session }
}

class URLSessionSwizzlerTests: XCTestCase {
    var session: URLSession { URLSession.shared }
    let modifiedURL = URL(string: "https://foo.bar.modified")!

    override func tearDown() {
        super.tearDown()
        MethodSwizzler.shared.unsafe_unswizzleALL()
        Swizzler.hasSwizzledBefore = false
    }

    func test_dataTask_urlCompletion_alwaysIntercept() {
        let completionExpectation = XCTestExpectation(description: "completionExpectation")
        let interceptorTuple = buildInterceptorTuple(modifiedURL: modifiedURL)

        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptorTuple.block))

        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in
            completionExpectation.fulfill()
        }

        XCTAssertNotEqual(task.originalRequest?.url, URL.mockAny())
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

        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptorTuple.block))

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in
            completionExpectation.fulfill()
        }

        XCTAssertNotEqual(task.originalRequest?.url, URL.mockAny())
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

        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptor))

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in }

        XCTAssertEqual(task.originalRequest?.url, modifiedURL)
    }
}

// MARK: - 3rd party swizzlers

class ThirdPartySwizzlingTests: XCTestCase {
    var session: URLSession { URLSession.shared }
    let timeout: TimeInterval = 0.1

    var thirdPartySwizzler = ExchangingThirdPartySwizzler()
    override func tearDown() {
        super.tearDown()
        MethodSwizzler.shared.unsafe_unswizzleALL()
        thirdPartySwizzler.unswizzle()
    }

    func test_3rdPartySwizzler() {
        let dataTaskURLExpc = XCTestExpectation(description: "dataTaskURLExpc")
        thirdPartySwizzler.swizzle_dataTask_url_completion(expectation: dataTaskURLExpc)

        let dataTaskRequestExpc = XCTestExpectation(description: "dataTaskRequestExpc")
        thirdPartySwizzler.swizzle_dataTask_request_completion(expectation: dataTaskRequestExpc)

        session.dataTask(with: URL.mockAny()) { _, _, _ in }
        session.dataTask(with: URLRequest.mockAny()) { _, _, _ in }

        wait(for: [dataTaskURLExpc, dataTaskRequestExpc], timeout: timeout)
    }

    /*

    // NOTE: RUMM-452 dataTaskWithURL WITH interception changes execution path to dataTaskWithRequest
    func test_3rdPartySwizzler_withDatadog_dataTaskWithURL_withoutInterception() {
        let dataTaskURLExpc = XCTestExpectation(description: "dataTaskURLExpc")
        thirdPartySwizzler.swizzle_dataTask_url_completion(expectation: dataTaskURLExpc)

        let interceptorTuple = buildInterceptorTuple(modifiedURL: nil)
        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptorTuple.block))

        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in }
        XCTAssert(task.isKind(of: URLSessionTask.self))

        wait(for: [interceptorTuple.interceptionExpectation, dataTaskURLExpc], timeout: timeout, enforceOrder: true)
    }

    func test_3rdPartySwizzler_withDatadog_dataTaskWithRequest_withoutInterception() {
        let dataTaskRequestExpc = XCTestExpectation(description: "dataTaskRequestExpc")
        thirdPartySwizzler.swizzle_dataTask_request_completion(expectation: dataTaskRequestExpc)

        let interceptorTuple = buildInterceptorTuple(modifiedURL: nil)
        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptorTuple.block))

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in }
        XCTAssert(task.isKind(of: URLSessionTask.self))

        wait(for: [interceptorTuple.interceptionExpectation, dataTaskRequestExpc], timeout: timeout, enforceOrder: true)
    }

    func test_3rdPartySwizzler_withDatadog_dataTaskWithRequest_withInterception() {
        let dataTaskRequestExpc = XCTestExpectation(description: "dataTaskRequestExpc")
        thirdPartySwizzler.swizzle_dataTask_request_completion(expectation: dataTaskRequestExpc)

        let interceptorTuple = buildInterceptorTuple(modifiedURL: URL.mockAny())
        XCTAssertNoThrow(try Swizzler.swizzleOnce(using: interceptorTuple.block))

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in }
        XCTAssert(task.isKind(of: URLSessionTask.self))

        wait(for: [interceptorTuple.interceptionExpectation, dataTaskRequestExpc], timeout: timeout, enforceOrder: true)
    }

 */

    func todo_test_3rdPartySwizzler_withDatadog_resume() {
        // TODO: RUMM-452
        // We need a way in which 3rd party swizzling is done BEFORe Datadog swizzling
        //
        // URLSessionTask.resume is Datadog-swizzled within dataTaskWithURL/Request methods implicitly as we need to swizzle private subclasses
        // We need a way to inject 3rd party swizzler between dataTask creation and task swizzling, which is a very narrow period
    }
}
