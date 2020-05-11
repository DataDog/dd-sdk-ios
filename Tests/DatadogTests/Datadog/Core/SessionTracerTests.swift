/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import Datadog
import _Datadog_Private

private extension String {
    init(fromUnsafePtr unsafePtr: UnsafePointer<Int8>) {
        self.init(format: "%s", unsafePtr)
    }
}

class SessionTracerTests: XCTestCase {
    private let injectedHeaders: [String: String] = ["custom-header-field": "custom-header-value"]

    private var swizzledSession: URLSession? = nil
    private func setupTracedSession() -> URLSession {
        self.swizzledSession = URLSession(configuration: .default)
        let requestInterceptor: (URLRequest) -> URLRequest = { originalRequest in
            var modifiedRequest = originalRequest
            modifiedRequest.allHTTPHeaderFields = self.injectedHeaders
            return modifiedRequest
        }
        let taskObserver: (URLSessionTask) -> Void = { observedTask in
            XCTAssertNotNil(observedTask)
        }
        try! Swizzler.swizzle(
            self.swizzledSession!,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver,
            enforceDynamicClassCreation: true
        )

        return self.swizzledSession!
    }

    private func tearDownTracedSession() {
        try! Swizzler.unswizzle(
            self.swizzledSession,
            andRemoveDynamicClass: true
        )
    }

    func testSwizzlingNotThrow() {
        let session = URLSession(configuration: .default)
        let originalKlass: AnyClass! = object_getClass(session) // swiftlint:disable:this implicitly_unwrapped_optional
        let originalKlassName = String(fromUnsafePtr: class_getName(originalKlass))
        do {
            try Datadog.trace(session)
        } catch {
            XCTFail("Datadog.trace: should NOT throw")
        }

        guard let klass: AnyClass = object_getClass(session), let superklass: AnyClass = class_getSuperclass(klass) else {
            XCTFail("New class of session instance should be obtained")
            return
        }
        let klassName = String(fromUnsafePtr: class_getName(klass))
        let superklassName = String(fromUnsafePtr: class_getName(superklass))

        XCTAssertEqual(originalKlassName, superklassName, "Original class should be new superclass")
        XCTAssert(klassName.contains(originalKlassName), "New class name should be a prefix-ed version of original class name")
        XCTAssert(session.isKind(of: URLSession.self))
    }

    func testInjectedMethods() {
        /*
         1. call Swizzler.swizzle(session:requestInterceptor:taskObserver:)
         2. expect custom interceptor and observer to run
         NOTE: this tests "injected_" prefixed methods in TemplateURLSession
         */
        let session = URLSession(configuration: .default)

        let requestInterceptionExpectation = expectation(description: "request interception expectation")
        let requestInterceptor: (URLRequest) -> URLRequest = { originalRequest in
            requestInterceptionExpectation.fulfill()
            return originalRequest
        }
        let taskObservationExpectation = expectation(description: "task observation expectation")
        let taskObserver: (URLSessionTask) -> Void = { observedTask in
            XCTAssertNotNil(observedTask)
            taskObservationExpectation.fulfill()
        }
        try! Swizzler.swizzle(
            session,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver,
            enforceDynamicClassCreation: true
        )

        let url = URL(string: "http://foo.bar")!
        _ = session.dataTask(with: url)

        wait(for: [requestInterceptionExpectation, taskObservationExpectation], timeout: 0.1, enforceOrder: true)
    }

    // MARK: - URLSessionDataTask methods
    func testDataTaskWithURL() {
        let url = URL(string: "http://foo.bar")!
        let task = setupTracedSession().dataTask(with: url)

        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)

        tearDownTracedSession()
    }
//    func testDataTaskWithURLRequest() {
//        let url = URL(string: "http://foo.bar")!
//        let request = URLRequest(url: url)
//        let task = setupTracedSession().dataTask(with: request)
//
//        XCTAssertEqual(task.originalRequest?.allHTTPHeaderFields, injectedHeaders)
//
//        tearDownTracedSession()
//    }
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

    // TODO: RUMM-300 URLSessionUploadTask methods

    // TODO: RUMM-300 URLSessionDownloadTask methods

    func testOriginalClassGetsSwizzledBy3rdParty() {
        /*
         1. call Datadog.trace(session)
         2. swizzle any method in session.superclass
         3. expect the swizzled superclass method to run
         NOTE: this tests "super_" prefixed methods in TemplateURLSession
         */
        XCTAssert(true)
    }

    func testSwizzleMultipleTimes() {
        /*
         1. call Datadog.trace(session) multiple times consecutively
         2. expect the first call to take longer than the last ones
         NOTE: this tests dynamic class cache in Swizzler.m
         */
        XCTAssert(true)
    }
}
