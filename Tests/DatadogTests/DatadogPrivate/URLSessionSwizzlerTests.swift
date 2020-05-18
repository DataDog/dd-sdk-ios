/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import _Datadog_Private
@testable import Datadog

class URLSessionSwizzlerTests: XCTestCase {
    private typealias RequestInterceptor = URLSessionSwizzler.RequestInterceptorIMP
    private typealias TaskObserver = URLSessionSwizzler.TaskObserverIMP

    private let injectedHeaders: [String: String] = ["custom-header-field": "custom-header-value"]

    private var swizzledSession: URLSession? = nil
    private func setupTracedSession(with configuration: URLSessionConfiguration = .default) -> URLSession {
        self.swizzledSession = URLSession(configuration: configuration)
        let requestInterceptor: RequestInterceptor = { _, originalRequest in
            var modifiedRequest = originalRequest
            modifiedRequest.allHTTPHeaderFields = self.injectedHeaders
            return modifiedRequest
        }
        let taskObserver: TaskObserver = {
            XCTAssertNotNil($1)
        }
        try! URLSessionSwizzler.swizzle(
            self.swizzledSession!,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver
        )
        return self.swizzledSession!
    }

    private func tearDownTracedSession(_ swizzledSession: URLSession? = nil) {
        let optionalSession = swizzledSession ?? self.swizzledSession
        if let sessionToUnswizzle = optionalSession {
            try? URLSessionSwizzler.unswizzle(sessionToUnswizzle, disposeDynamicClass: true)
        }
    }

    // MARK: - General swizzler tests

    func testSwizzlingNotThrow() {
        let session = URLSession(configuration: .default)
        let originalKlass: AnyClass! = object_getClass(session) // swiftlint:disable:this implicitly_unwrapped_optional
        let originalKlassName = String(fromUnsafePtr: class_getName(originalKlass))
        let requestInterceptor: RequestInterceptor = { return $1 }
        let taskObserver: TaskObserver = { _, _ in }

        XCTAssertNoThrow(
            try URLSessionSwizzler.swizzle(
                session,
                requestInterceptor: requestInterceptor,
                taskObserver: taskObserver
            )
        )

        guard let klass: AnyClass = object_getClass(session), let superklass: AnyClass = class_getSuperclass(klass) else {
            XCTFail("New class of session instance should be obtained")
            return
        }
        let klassName = String(fromUnsafePtr: class_getName(klass))
        let superklassName = String(fromUnsafePtr: class_getName(superklass))

        XCTAssertEqual(originalKlassName, superklassName, "Original class should be new superclass")
        XCTAssert(klassName.contains(originalKlassName), "New class name should be a prefix-ed version of original class name")
        XCTAssert(session.isKind(of: URLSession.self))

        tearDownTracedSession(session)
    }

    func testInjectedMethods() {
        /*
         1. call URLSessionSwizzler.swizzle(session:requestInterceptor:taskObserver:)
         2. expect custom interceptor and observer to run
         NOTE: this tests "injected_" prefixed methods in TemplateURLSession
         */
        let session = URLSession(configuration: .default)

        let requestInterceptionExpectation = expectation(description: "request interception expectation")
        let requestInterceptor: RequestInterceptor = {
            requestInterceptionExpectation.fulfill()
            return $1
        }
        let taskObservationExpectation = expectation(description: "task observation expectation")
        let taskObserver: TaskObserver = {
            XCTAssertNotNil($1)
            taskObservationExpectation.fulfill()
        }
        try! URLSessionSwizzler.swizzle(
            session,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver
        )

        let url = URL(string: "http://foo.bar")!
        _ = session.dataTask(with: url)

        wait(for: [requestInterceptionExpectation, taskObservationExpectation], timeout: 0.1, enforceOrder: true)
        tearDownTracedSession(session)
    }

    func testThirdPartySwizzler() {
        /*
         1. call Datadog.trace(session)
         2. swizzle any method in session.superclass
         3. expect the swizzled superclass method to run
         NOTE: this tests "super_" prefixed methods in TemplateURLSession
         */
        let session = URLSession(configuration: .default)

        let expc = expectation(description: "3rd party swizzler expectation")
        let thirdPartySwizzler = ThirdPartySessionSwizzler()
        thirdPartySwizzler.swizzleDataTaskWithURLRequestInSuperclass(
            swizzledSession: session,
            expectation: expc
        )

        let request = URLRequest(url: URL(string: "http://foo.bar")!)
        _ = session.dataTask(with: request)

        wait(for: [expc], timeout: 0.1)
        tearDownTracedSession()
    }

    func testOriginalClassGetsSwizzledBy3rdParty() {
        /*
         1. call Datadog.trace(session)
         2. swizzle any method in session.superclass
         3. expect the swizzled superclass method to run
         NOTE: this tests "super_" prefixed methods in TemplateURLSession
         */
        let session = setupTracedSession()

        let expc = expectation(description: "3rd party swizzler expectation")
        let thirdPartySwizzler = ThirdPartySessionSwizzler()
        thirdPartySwizzler.swizzleDataTaskWithURLRequestInSuperclass(
            swizzledSession: session,
            expectation: expc
        )

        let request = URLRequest(url: URL(string: "http://foo.bar")!)
        _ = session.dataTask(with: request)

        wait(for: [expc], timeout: 0.1)
        tearDownTracedSession()
    }

    func testSwizzlingTheSwizzled() {
        let interceptor: RequestInterceptor = { $1 }
        let observer: TaskObserver = { _, _ in }
        let session = URLSession(configuration: .default)
        defer {
            try! URLSessionSwizzler.unswizzle(session, disposeDynamicClass: true)
        }
        for _ in 0...5 {
            XCTAssertNoThrow(
                try URLSessionSwizzler.swizzle(
                    session,
                    requestInterceptor: interceptor,
                    taskObserver: observer
                )
            )
        }
    }

    func testSwizzleMultipleTimes() {
        /*
         1. call Datadog.trace(session) multiple times consecutively
         2. expect the first call to take longer than the last ones
         NOTE: this tests dynamic class cache in URLSessionSwizzler.m
         */
        let session1 = URLSession(configuration: .default)
        let session2 = URLSession(configuration: .default)
        let session3 = URLSession(configuration: .default)

        try! [session1, session2, session3].forEach { session in
            XCTAssertNoThrow(
                try URLSessionSwizzler.swizzle(
                    session,
                    requestInterceptor: { $1 },
                    taskObserver: { _, _ in }
                )
            )
        }

        tearDownTracedSession(session1)
        tearDownTracedSession(session2)
        tearDownTracedSession(session3)
    }

    func testConcurrentSwizzling() {
        let requestInterceptor: RequestInterceptor = { $1 }
        let taskObserver: TaskObserver = { _, _ in }
        let iterationCount = 5
        let url = URL(string: "http://foo.bar")!
        let swizzledSessions: [(URLSession, XCTestExpectation)]
        swizzledSessions = (0..<iterationCount).map { _ in
            return (URLSession(configuration: .default), expectation(description: "concurrent expectation \(UUID().uuidString)"))
        }
        DispatchQueue.concurrentPerform(iterations: iterationCount) { iteration in
            do {
                try URLSessionSwizzler.swizzle(swizzledSessions[iteration].0, requestInterceptor: requestInterceptor, taskObserver: taskObserver)
            } catch {
                XCTAssertNil(error)
            }
            let task = swizzledSessions[iteration].0.dataTask(with: url)

            XCTAssertNotNil(task)
            swizzledSessions[iteration].1.fulfill()
        }
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - URLSessionDataTask methods
    func testDataTaskWithURL() {
        let url = URL(string: "http://foo.bar")!
        let task = setupTracedSession().dataTask(with: url)

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }
    func testDataTaskWithURLRequest() {
        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let task = setupTracedSession().dataTask(with: request)

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }
    func testDataTaskWithURLCompletionHandler() {
        let url = URL(string: "http://foo.bar")!
        let task = setupTracedSession().dataTask(with: url) { _,_,_ in }

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }
    func testDataTaskWithURLRequestCompletionHandler() {
        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let task = setupTracedSession().dataTask(with: request) { _,_,_ in }

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }

    func testAllDataTaskMethodsAtOnce() {
        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let session = setupTracedSession()

        let dataTaskURL = session.dataTask(with: url)
        let dataTaskRequest = session.dataTask(with: request)
        let dataTaskURLCompletion = session.dataTask(with: url) { _,_,_ in }
        let dataTaskRequestCompletion = session.dataTask(with: request) { _,_,_ in }

        XCTAssertEqual(dataTaskURL.originalRequest?.allHTTPHeaderFields, injectedHeaders)
        XCTAssertEqual(dataTaskRequest.originalRequest?.allHTTPHeaderFields, injectedHeaders)
        XCTAssertEqual(dataTaskURLCompletion.originalRequest?.allHTTPHeaderFields, injectedHeaders)
        XCTAssertEqual(dataTaskRequestCompletion.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }

    func testSwizzledBackgroundSession() {
        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let session = setupTracedSession(with: .background(withIdentifier: "unit-test-session"))

        let expectedHeaders = injectedHeaders
        let bgExpectation = expectation(description: "background expectation")

        DispatchQueue.global(qos: .background).async {
            let dataTaskURL = session.dataTask(with: url)
            let dataTaskRequest = session.dataTask(with: request)

            XCTAssertEqual(dataTaskURL.originalRequest?.allHTTPHeaderFields, expectedHeaders)
            XCTAssertEqual(dataTaskRequest.originalRequest?.allHTTPHeaderFields, expectedHeaders)

            bgExpectation.fulfill()
        }

        wait(for: [bgExpectation], timeout: 0.1)
        tearDownTracedSession()
    }

    func testSwizzledBackgroundSessionWithCompletionHandlers() {
            let url = URL(string: "http://foo.bar")!
            let request = URLRequest(url: url)
            let session = setupTracedSession(with: .background(withIdentifier: "unit-test-session"))

            let bgExpectation = expectation(description: "background expectation")

            DispatchQueue.global(qos: .background).async {
                do {
                    try objcExceptionHandler.rethrowToSwift {
                        session.dataTask(with: url) { _,_,_ in }
                    }
                } catch {
                    XCTAssertNotNil(error, "Background session doesn't support completion handlers")
                }
                do {
                    try objcExceptionHandler.rethrowToSwift {
                        session.dataTask(with: request) { _,_,_ in }
                    }
                } catch {
                    XCTAssertNotNil(error, "Background session doesn't support completion handlers")
                }

                bgExpectation.fulfill()
            }
            wait(for: [bgExpectation], timeout: 0.1)
            tearDownTracedSession()
    }

    // TODO: RUMM-300 URLSessionUploadTask methods

    // TODO: RUMM-300 URLSessionDownloadTask methods

}

// MARK: - Utilities

private extension String {
    init(fromUnsafePtr unsafePtr: UnsafePointer<Int8>) {
        self.init(format: "%s", unsafePtr)
    }
}

private class ThirdPartySessionSwizzler {
    private let selector = #selector(URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask)
    private(set) var isSwizzled: Bool = false
    private var originalClass: AnyClass?
    private var originalIMP: IMP?

    func swizzleDataTaskWithURLRequestInSuperclass(
        swizzledSession: URLSession,
        expectation: XCTestExpectation
    ) {
        if isSwizzled {
            return
        }
        originalClass = class_getSuperclass(object_getClass(swizzledSession))!
        let method: Method = class_getInstanceMethod(originalClass, selector)!
        originalIMP = method_getImplementation(method)

        typealias DataTaskWithRequestSignature = @convention(block) (AnyObject, URLRequest) -> URLSessionDataTask
        let newIMPBlock: DataTaskWithRequestSignature = { impSelf, impRequest in
            expectation.fulfill()
            return URLSession.shared.dataTask(with: impRequest.url!)
        }
        let newImp: IMP = imp_implementationWithBlock(newIMPBlock)
        method_setImplementation(method, newImp)

        isSwizzled = true
    }

    func unswizzle() {
        guard isSwizzled,
            let swizzledClass = originalClass,
            let swizzledImp = originalIMP else {
                return
        }
        let swizzledMethod: Method = class_getInstanceMethod(swizzledClass, selector)!
        method_setImplementation(swizzledMethod, swizzledImp)
    }

    deinit {
        unswizzle()
    }
}
