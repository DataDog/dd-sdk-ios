/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
private extension URLSession {
    @objc
    func thirdPartySwizzled_dataTaskURL(_ url: URL, completion: @escaping CompletionHandler) -> URLSessionDataTask {
        NotificationCenter.default.post(name: ExchangingThirdPartySwizzler.swizzleNotification_dataTask_URL, object: nil)
        return thirdPartySwizzled_dataTaskURL(url, completion: completion)
    }
    @objc
    func thirdPartySwizzled_dataTaskRequest(_ request: URLRequest, completion: @escaping CompletionHandler) -> URLSessionDataTask {
        NotificationCenter.default.post(name: ExchangingThirdPartySwizzler.swizzleNotification_dataTask_request, object: nil)
        return thirdPartySwizzled_dataTaskRequest(request, completion: completion)
    }
}
private extension URLSessionTask {
    @objc
    func swizzled_resume() {
        NotificationCenter.default.post(name: ExchangingThirdPartySwizzler.swizzleNotification_resume, object: nil)
    }
}

class ExchangingThirdPartySwizzler {
    fileprivate static let swizzleNotification_dataTask_URL = Notification.Name("swizzledDataTaskWithURLNotification")
    fileprivate static let swizzleNotification_dataTask_request = Notification.Name("swizzledDataTaskWithRequestNotification")
    fileprivate static let swizzleNotification_resume = Notification.Name("resumeNotification")

    private static let targetClass: AnyClass = URLSession.self
    private var taskTargetClass: AnyClass?

    private let selector_url_completion: Selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
    private let swizzle_selector_url_completion: Selector = #selector(URLSession.thirdPartySwizzled_dataTaskURL(_:completion:))

    private let selector_request_completion: Selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)
    private let swizzle_selector_request_completion: Selector = #selector(URLSession.thirdPartySwizzled_dataTaskRequest(_:completion:))

    private let selector_resume: Selector = #selector(URLSessionTask.resume)
    private let swizzle_selector_resume: Selector = #selector(URLSessionTask.swizzled_resume)

    private var observer_dataTask_url_completion: NSObjectProtocol? = nil
    private var observer_dataTask_request_completion: NSObjectProtocol? = nil
    private var observer_resume: NSObjectProtocol? = nil

    private var cached_origIMP_dataTask_URL: IMP? = nil
    private var cached_swizzleIMP_dataTask_URL: IMP? = nil

    private var cached_origIMP_dataTask_request: IMP? = nil
    private var cached_swizzleIMP_dataTask_request: IMP? = nil

    private var cached_origIMP_resume: IMP? = nil
    private var cached_swizzleIMP_resume: IMP? = nil

    func swizzle_dataTask_url_completion(expectation: XCTestExpectation?) {
        let origMethod = class_getInstanceMethod(Self.targetClass, selector_url_completion)!
        cached_origIMP_dataTask_URL = method_getImplementation(origMethod)

        let swizzledMethod = class_getInstanceMethod(Self.targetClass, swizzle_selector_url_completion)!
        cached_swizzleIMP_dataTask_URL = method_getImplementation(swizzledMethod)

        method_setImplementation(origMethod, cached_swizzleIMP_dataTask_URL!)
        method_setImplementation(swizzledMethod, cached_origIMP_dataTask_URL!)

        observer_dataTask_url_completion = NotificationCenter.default.addObserver(
            forName: Self.swizzleNotification_dataTask_URL,
            object: nil,
            queue: nil
        ) { _ in
            expectation?.fulfill()
        }
    }

    func swizzle_dataTask_request_completion(expectation: XCTestExpectation?) {
        let origMethod = class_getInstanceMethod(Self.targetClass, selector_request_completion)!
        cached_origIMP_dataTask_request = method_getImplementation(origMethod)

        let swizzledMethod = class_getInstanceMethod(Self.targetClass, swizzle_selector_request_completion)!
        cached_swizzleIMP_dataTask_request = method_getImplementation(swizzledMethod)

        method_setImplementation(origMethod, cached_swizzleIMP_dataTask_request!)
        method_setImplementation(swizzledMethod, cached_origIMP_dataTask_request!)

        observer_dataTask_request_completion = NotificationCenter.default.addObserver(
            forName: Self.swizzleNotification_dataTask_request,
            object: nil,
            queue: nil
        ) { _ in
            expectation?.fulfill()
        }
    }

    func swizzle_resume(_ task: URLSessionTask, expectation: XCTestExpectation?) {
        let taskClass: AnyClass = object_getClass(task)!
        taskTargetClass = taskClass
        let origMethod = class_getInstanceMethod(taskClass, selector_resume)!
        cached_origIMP_resume = method_getImplementation(origMethod)

        let swizzledMethod = class_getInstanceMethod(taskClass, swizzle_selector_resume)!
        cached_swizzleIMP_resume = method_getImplementation(swizzledMethod)

        method_setImplementation(origMethod, cached_swizzleIMP_resume!)
        method_setImplementation(swizzledMethod, cached_origIMP_resume!)

        observer_resume = NotificationCenter.default.addObserver(
            forName: Self.swizzleNotification_resume,
            object: nil,
            queue: nil
        ) { _ in
            expectation?.fulfill()
        }
    }

    func unswizzle() {
        if let someOrigIMP = cached_origIMP_dataTask_URL,
            let someSwizzleIMP = cached_swizzleIMP_dataTask_URL {
            method_setImplementation(
                class_getInstanceMethod(Self.targetClass, selector_url_completion)!,
                someOrigIMP
            )
            method_setImplementation(
                class_getInstanceMethod(Self.targetClass, swizzle_selector_url_completion)!,
                someSwizzleIMP
            )
        }
        if let someOrigIMP = cached_origIMP_dataTask_request,
            let someSwizzleIMP = cached_swizzleIMP_dataTask_request {
            method_setImplementation(
                class_getInstanceMethod(Self.targetClass, selector_request_completion)!,
                someOrigIMP
            )
            method_setImplementation(
                class_getInstanceMethod(Self.targetClass, swizzle_selector_request_completion)!,
                someSwizzleIMP
            )
        }
        if let someTargetClass = taskTargetClass,
            let someOrigIMP = cached_origIMP_resume,
            let someSwizzleIMP = cached_swizzleIMP_resume {
            method_setImplementation(
                class_getInstanceMethod(someTargetClass, selector_resume)!,
                someOrigIMP
            )
            method_setImplementation(
                class_getInstanceMethod(someTargetClass, swizzle_selector_resume)!,
                someSwizzleIMP
            )
        }
    }
}

/*

class DirectThirdPartySwizzler {
    private var origIMP_URL: IMP? = nil
    private var origIMP_request: IMP? = nil

    func swizzle_dataTask_url_completion(expectation: XCTestExpectation) {
        typealias TypedIMP = @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask
        typealias TypedBlockIMP = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask

        let sel = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
        let method = class_getInstanceMethod(URLSession.self, sel)!
        let originalIMP = method_getImplementation(method)
        let typedOriginalImp = unsafeBitCast(originalIMP, to: TypedIMP.self)
        origIMP_URL = originalIMP

        let newImpBlock: TypedBlockIMP = { impSelf, impURL, impCompletion -> URLSessionDataTask in
            expectation.fulfill()
            return typedOriginalImp(impSelf, sel, impURL, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        method_setImplementation(method, newImp)
    }

    func swizzle_dataTask_request_completion(expectation: XCTestExpectation) {
        typealias TypedIMP = @convention(c) (URLSession, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        typealias TypedBlockIMP = @convention(block) (URLSession, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask

        let sel = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)
        let method = class_getInstanceMethod(URLSession.self, sel)!
        let originalIMP = method_getImplementation(method)
        let typedOriginalImp = unsafeBitCast(originalIMP, to: TypedIMP.self)
        origIMP_request = originalIMP

        let newImpBlock: TypedBlockIMP = { impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
            expectation.fulfill()
            return typedOriginalImp(impSelf, sel, impURLRequest, impCompletion)
        }
        let newImp: IMP = imp_implementationWithBlock(newImpBlock)
        method_setImplementation(method, newImp)
    }

    func unswizzle() {
        if let someIMP = origIMP_URL {
            let sel = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
            let method = class_getInstanceMethod(URLSession.self, sel)!
            method_setImplementation(method, someIMP)
        }
        if let someIMP = origIMP_request {
            let sel = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)
            let method = class_getInstanceMethod(URLSession.self, sel)!
            method_setImplementation(method, someIMP)
        }
    }
}

*/
