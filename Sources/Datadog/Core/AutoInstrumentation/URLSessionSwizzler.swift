/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Block type to hook into URLSession methods:
/// dataTaskWithURL:completion: and dataTaskWithRequest:completion:
/// Takes an URL and if it is to be intercepted, returns a TaskObserver and additional HTTP headers
/// otherwise, returns nil
internal typealias RequestInterceptor = (URL?) -> InterceptionResult?
internal typealias InterceptionResult = (taskObserver: TaskObserver, httpHeaders: [String: String])

/// Block to be executed at task starting and completion by URLSessionSwizzler
/// starting event is passed at task.resume()
/// completed event is passed when task's completion handler is being executed
internal typealias TaskObserver = (TaskObservationEvent) -> Void
internal enum TaskObservationEvent: Equatable {
    case starting
    case completed
}

internal class URLSessionSwizzler {
    let dataTaskWithURL: DataTaskWithURL
    let dataTaskwithRequest: DataTaskWithRequest
    let resume: Resume

    init() throws {
        self.dataTaskWithURL = try DataTaskWithURL()
        self.dataTaskwithRequest = try DataTaskWithRequest()
        self.resume = try Resume()
    }

    static var hasSwizzledBefore = false
    @discardableResult
    func swizzleOnce(using interceptor: @escaping RequestInterceptor) -> Bool {
        if Self.hasSwizzledBefore {
            consolePrint("URLSession is already swizzled before!")
            return false
        }
        dataTaskWithURL.swizzle(using: interceptor, resumeSwizzler: resume)
        dataTaskwithRequest.swizzle(using: interceptor, resumeSwizzler: resume)
        Self.hasSwizzledBefore = true
        return true
    }

    // MARK: - Private

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    class DataTaskWithURL: MethodSwizzler <
        @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask,
        @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
    > {
        private static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)

        private let method: FoundMethod
        override init() throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            try super.init()
        }

        func swizzle(using interceptor: @escaping RequestInterceptor, resumeSwizzler: Resume) {
            typealias BlockIMP = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
            swizzle(method) { currentTypedImp -> BlockIMP in
                return { impSelf, impURL, impCompletion -> URLSessionDataTask in
                    guard let interceptionResult = interceptor(impURL) else {
                        return currentTypedImp(impSelf, Self.selector, impURL, impCompletion)
                    }

                    weak var blockTask: URLSessionDataTask? = nil
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }
                    let task = currentTypedImp(impSelf, Self.selector, impURL, modifiedCompletion)
                    try? resumeSwizzler.swizzleIfNeeded(in: task)
                    task.payload = interceptionResult.taskObserver
                    blockTask = task
                    return task
                }
            }
        }
    }

    class DataTaskWithRequest: MethodSwizzler <
        @convention(c) (URLSession, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask,
        @convention(block) (URLSession, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
    > {
        private static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)

        private let method: FoundMethod
        override init() throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            try super.init()
        }

        func swizzle(using interceptor: @escaping RequestInterceptor, resumeSwizzler: Resume) {
            typealias BlockIMP = @convention(block) (URLSession, URLRequest, @escaping URLSessionSwizzler.CompletionHandler) -> URLSessionDataTask

            self.swizzle(self.method) { typedCurrentImp -> BlockIMP in
                return { impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
                    guard let interceptionResult = interceptor(impURLRequest.url) else {
                        return typedCurrentImp(impSelf, Self.selector, impURLRequest, impCompletion)
                    }

                    weak var blockTask: URLSessionDataTask? = nil
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }
                    let modifiedRequest = impURLRequest.merging(interceptionResult.httpHeaders)
                    let task = typedCurrentImp(impSelf, Self.selector, modifiedRequest, modifiedCompletion)
                    try? resumeSwizzler.swizzleIfNeeded(in: task)
                    task.payload = interceptionResult.taskObserver
                    blockTask = task
                    return task
                }
            }
        }
    }

    class Resume: MethodSwizzler <
        @convention(c) (URLSessionTask, Selector) -> Void,
        @convention(block) (URLSessionTask) -> Void
    > {
        private static let selector = #selector(URLSessionTask.resume)

        /// NOTE: RUMM-452
        /// URLSessionTask.resume is not called by its subclasses!
        /// Therefore, we swizzle this method in the subclass.
        /// This is unlike swizzling dataTaskURL/Request: in URLSession base class
        func swizzleIfNeeded(in task: URLSessionTask) throws {
            guard let taskClass = object_getClass(task) else {
                userLogger.error("Unable to swizzle `URLSessionTask`: \(task) - the trace will not be created.")
                return
            }
            let foundMethod = try Self.findMethod(with: Self.selector, in: taskClass)
            // NOTE: RUMM-452 We will probably not need to swizzle tasks every time
            // "onlyIfNonSwizzled: true" lets us perform swizzling in given class if not done before
            typealias BlockIMP = @convention(block) (URLSessionTask) -> Void
            swizzle(
                foundMethod,
                impProvider: { currentTypedImp -> BlockIMP in
                    return { impSelf in
                        impSelf.payload?(.starting)
                        return currentTypedImp(impSelf, Self.selector)
                    }
                },
                onlyIfNonSwizzled: true
            )
        }
    }
}

private extension URLRequest {
    func merging(_ httpHeaders: [String: String]) -> URLRequest {
        var modifiedRequest = self
        for pair in httpHeaders {
            if modifiedRequest.value(forHTTPHeaderField: pair.key) == nil {
                modifiedRequest.setValue(pair.value, forHTTPHeaderField: pair.key)
            }
        }
        return modifiedRequest
    }
}

/// payload is a TaskObserver, executed in task.resume() and completion
private extension URLSessionTask {
    /// NOTE: RUMM-452 KVO on task.state could be utilized instead of manually swizzling every task object
    /// if we switch to KVO from swizzle(task), this shouldn't require refactoring and contained within this file only
    /// therefore we keep payload as an implementation detail of URLSessionSwizzler.
    /// unfortunately, KVO in Swift was broken until iOS 13 and task.state didn't seem reliable according to online crash reports
    private static var payloadAssociationKey: UInt8 = 0
    var payload: TaskObserver? {
        get { objc_getAssociatedObject(self, &Self.payloadAssociationKey) as? TaskObserver }
        set { objc_setAssociatedObject(self, &Self.payloadAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
