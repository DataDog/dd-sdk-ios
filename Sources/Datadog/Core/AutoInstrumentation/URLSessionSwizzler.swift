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
internal struct InterceptionResult {
    let taskObserver: TaskObserver
    let httpHeaders: [String: String]
}

/// Block to be executed at task starting and completion by URLSessionSwizzler
/// starting event is passed at task.resume()
/// completed event is passed when task's completion handler is being executed
internal typealias TaskObserver = (TaskObservationEvent) -> Void
internal enum TaskObservationEvent {
    case starting(URLRequest?)
    case completed(URLResponse?, Error?)
}

internal class URLSessionSwizzler {
    let dataTaskWithURL: DataTaskWithURL
    let dataTaskwithRequest: DataTaskWithRequest
    /// resume must be shared among URLSessionSwizzler instances
    /// to avoid swizzling task.resume() multiple times
    static let resume = Resume()

    init(with resume: Resume = URLSessionSwizzler.resume) throws {
        self.dataTaskWithURL = try DataTaskWithURL(resume: resume)
        self.dataTaskwithRequest = try DataTaskWithRequest(resume: resume)
    }

    func swizzle(using interceptor: @escaping RequestInterceptor) {
        dataTaskWithURL.swizzle(using: interceptor)
        dataTaskwithRequest.swizzle(using: interceptor)
    }

    // MARK: - Private

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    class DataTaskWithURL: MethodSwizzler <
        @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask,
        @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
    > {
        private static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)

        private let method: FoundMethod
        private let resume: Resume
        init(resume: Resume) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.resume = resume
            super.init()
        }

        func swizzle(using interceptor: @escaping RequestInterceptor) {
            typealias BlockIMP = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
            let resumeSwizzler = resume
            swizzle(method) { currentTypedImp -> BlockIMP in
                return { impSelf, impURL, impCompletion -> URLSessionDataTask in
                    guard let interceptionResult = interceptor(impURL) else {
                        return currentTypedImp(impSelf, Self.selector, impURL, impCompletion)
                    }
                    var taskObserver: TaskObserver? = interceptionResult.taskObserver
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        taskObserver?(.completed(origResponse, origError))
                    }
                    /// NOTE: RUMM-489 in iOS 11/12 dataTaskWithURL: calls dataTaskWithRequest: internally
                    /// we need to check if the originalRequest already has interceptor headers
                    /// if so, we don't intercept this request
                    let task = currentTypedImp(impSelf, Self.selector, impURL, modifiedCompletion)
                    if var request = task.originalRequest,
                        request.add(newHTTPHeaders: interceptionResult.httpHeaders) {
                        /// interception needed
                        try? resumeSwizzler.swizzleIfNeeded(in: task)
                        task.addPayload(interceptionResult.taskObserver)
                    } else {
                        /// do NOT intercept!
                        taskObserver = nil
                    }
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
        private let resume: Resume
        init(resume: Resume) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.resume = resume
            super.init()
        }

        func swizzle(using interceptor: @escaping RequestInterceptor) {
            typealias BlockIMP = @convention(block) (URLSession, URLRequest, @escaping URLSessionSwizzler.CompletionHandler) -> URLSessionDataTask
            let resumeSwizzler = resume
            self.swizzle(self.method) { typedCurrentImp -> BlockIMP in
                return { impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
                    var modifiedRequest = impURLRequest
                    guard let interceptionResult = interceptor(impURLRequest.url),
                        modifiedRequest.add(newHTTPHeaders: interceptionResult.httpHeaders) else {
                            return typedCurrentImp(impSelf, Self.selector, impURLRequest, impCompletion)
                    }
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        interceptionResult.taskObserver(.completed(origResponse, origError))
                    }
                    let task = typedCurrentImp(impSelf, Self.selector, modifiedRequest, modifiedCompletion)
                    try? resumeSwizzler.swizzleIfNeeded(in: task)
                    task.addPayload(interceptionResult.taskObserver)
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
                        impSelf.payloads?.forEach { $0(.starting(impSelf.currentRequest)) }
                        return currentTypedImp(impSelf, Self.selector)
                    }
                },
                onlyIfNonSwizzled: true
            )
        }
    }
}

private extension URLRequest {
    mutating func add(newHTTPHeaders httpHeaders: [String: String]) -> Bool {
        var modifiedRequest = self
        for pair in httpHeaders {
            if modifiedRequest.value(forHTTPHeaderField: pair.key) == nil {
                modifiedRequest.setValue(pair.value, forHTTPHeaderField: pair.key)
            } else {
                return false
            }
        }
        self = modifiedRequest
        return true
    }
}

/// payloads is an array TaskObservers, each one is executed in task.resume() and completion
private extension URLSessionTask {
    /// NOTE: RUMM-452 KVO on task.state could be utilized instead of manually swizzling every task object
    /// if we switch to KVO from swizzle(task), this shouldn't require refactoring and contained within this file only
    /// therefore we keep payload as an implementation detail of URLSessionSwizzler.
    /// unfortunately, KVO in Swift was broken until iOS 13 and task.state didn't seem reliable according to online crash reports
    private static var payloadAssociationKey: UInt8 = 0
    var payloads: [TaskObserver]? {
        return objc_getAssociatedObject(self, &Self.payloadAssociationKey) as? [TaskObserver]
    }
    func addPayload(_ payload: @escaping TaskObserver) {
        var current = payloads ?? [TaskObserver]()
        current.append(payload)
        objc_setAssociatedObject(self, &Self.payloadAssociationKey, current, .OBJC_ASSOCIATION_RETAIN)
    }
}
