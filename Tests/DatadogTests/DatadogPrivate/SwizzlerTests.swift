/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
import _Datadog_Private

class SwizzlerTests: XCTestCase {
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

    private func tearDownTracedSession(_ swizzledSession: URLSession? = nil) {
        try? Swizzler.unswizzle(
            swizzledSession ?? self.swizzledSession,
            andRemoveDynamicClass: true
        )
    }

    // MARK: - General swizzler tests

    func testSwizzlingNotThrow() {
        let session = URLSession(configuration: .default)
        let originalKlass: AnyClass! = object_getClass(session) // swiftlint:disable:this implicitly_unwrapped_optional
        let originalKlassName = String(fromUnsafePtr: class_getName(originalKlass))
        do {
            let requestInterceptor: (URLRequest) -> URLRequest = { return $0 }
            let taskObserver: (URLSessionTask) -> Void = { _ in }
            try Swizzler.swizzle(
                session,
                requestInterceptor: requestInterceptor,
                taskObserver: taskObserver,
                enforceDynamicClassCreation: true
            )
        } catch {
            XCTAssertNil(error)
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

        tearDownTracedSession(session)
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

    func testSwizzleMultipleTimes() {
        /*
         1. call Datadog.trace(session) multiple times consecutively
         2. expect the first call to take longer than the last ones
         NOTE: this tests dynamic class cache in Swizzler.m
         */
        let session1 = URLSession(configuration: .default)
        let session2 = URLSession(configuration: .default)
        let session3 = URLSession(configuration: .default)

        do {
            try Swizzler.swizzle(
                session1,
                requestInterceptor: { $0 },
                taskObserver: { _ in },
                enforceDynamicClassCreation: true
            )
            try Swizzler.swizzle(
                session2,
                requestInterceptor: { $0 },
                taskObserver: { _ in },
                enforceDynamicClassCreation: false
            )
            try Swizzler.swizzle(
                session3,
                requestInterceptor: { $0 },
                taskObserver: { _ in },
                enforceDynamicClassCreation: true
            )
            XCTFail("session3 swizzling with enforceDynamicClassCreation should throw!")
        } catch {
            let className1 = NSStringFromClass(object_getClass(session1)!)
            let className2 = NSStringFromClass(object_getClass(session2)!)
            let className3 = NSStringFromClass(object_getClass(session3)!)

            XCTAssertTrue(className1.contains("_Datadog"))
            XCTAssertEqual(className1, className2)
            XCTAssertFalse(className3.contains("_Datadog"))
            XCTAssertNotNil(error)
        }

        // tearDownTracedSession(session1/2) would result in EXC_BAD_ACCESS
        // Because tearDownTracedSession removes dynamic class by default
        // If we tearDown one of those instances, the other would be class-less -> EXC_BAD_ACCESS
        try? Swizzler.unswizzle(
            session1,
            andRemoveDynamicClass: false
        )
        try? Swizzler.unswizzle(
            session2,
            andRemoveDynamicClass: true
        )
        tearDownTracedSession(session3)
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
