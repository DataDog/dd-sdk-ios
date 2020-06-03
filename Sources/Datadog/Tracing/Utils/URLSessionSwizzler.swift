/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Block type to hook into URLSession methods:
/// dataTaskWithURL:completion: and dataTaskWithRequest:completion:
/// Takes original URLRequest and returns modified URLRequest with TaskObserver
internal typealias RequestInterceptor = (URLRequest) -> InterceptionResult?
internal typealias InterceptionResult = (modifiedRequest: URLRequest, taskObserver: TaskObserver)

/// Block to be executed at task starting and completion by URLSessionSwizzler
/// starting event is passed at task.resume()
/// completed event is passed when task's completion handler is being executed
internal typealias TaskObserver = (TaskObservationEvent) -> Void
internal enum TaskObservationEvent: Equatable {
    case starting
    case completed
}

// MARK: - Private

private let swizzler = MethodSwizzler.shared

internal enum URLSessionSwizzler {
    static var hasSwizzledBefore = false
    static func swizzleOnce(using interceptor: @escaping RequestInterceptor) throws {
        guard let dataTask_URL = DataTask_URL_Completion(),
            let dataTask_request = DataTask_Request_Completion() else {
                throw InternalError(description: "URLSession methods could not be found, thus not swizzled")
        }

        if hasSwizzledBefore {
            return
        }
        hasSwizzledBefore = true

        dataTask_URL.swizzle(using: interceptor)
        dataTask_request.swizzle(using: interceptor)
    }

    private typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    private struct DataTask_URL_Completion {
        private typealias TypedIMP = @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask
        private typealias TypedBlockIMP = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask
        private static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)

        let method: MethodSwizzler.FoundMethod
        init?() {
            guard let foundMethod = swizzler.findMethodRecursively(
                with: Self.selector,
                in: URLSession.self
                ) else {
                    return nil
            }
            self.method = foundMethod
        }

        func swizzle(using interceptor: @escaping RequestInterceptor) {
            let typedOriginalImp: TypedIMP = swizzler.currentImplementation(of: method)

            let newImpBlock: TypedBlockIMP = { impSelf, impURL, impCompletion -> URLSessionDataTask in
                if let interceptionResult = interceptor(impSelf.urlRequest(with: impURL)) {
                    weak var blockTask: URLSessionDataTask? = nil
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }
                    let task = impSelf.dataTask(with: interceptionResult.modifiedRequest, completionHandler: modifiedCompletion)
                    Resume.swizzleIfNeeded(in: task)
                    task.payload = interceptionResult.taskObserver
                    blockTask = task
                    return task
                }

                return typedOriginalImp(impSelf, Self.selector, impURL, impCompletion)
            }
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)

            swizzler.set(newIMP: newImp, for: method)
        }
    }

    private struct DataTask_Request_Completion {
        private typealias TypedIMP = @convention(c) (URLSession, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        private typealias TypedBlockIMP = @convention(block) (URLSession, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        private static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)

        let method: MethodSwizzler.FoundMethod
        init?() {
            guard let foundMethod = swizzler.findMethodRecursively(
                with: Self.selector,
                in: URLSession.self
                ) else {
                    return nil
            }
            self.method = foundMethod
        }

        func swizzle(using interceptor: @escaping RequestInterceptor) {
            let typedOriginalImp: TypedIMP = swizzler.currentImplementation(of: method)

            let newImpBlock: TypedBlockIMP = { impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
                if let interceptionResult = interceptor(impURLRequest) {
                    weak var blockTask: URLSessionDataTask? = nil

                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }

                    let task = typedOriginalImp(impSelf, Self.selector, interceptionResult.modifiedRequest, modifiedCompletion)
                    Resume.swizzleIfNeeded(in: task)
                    task.payload = interceptionResult.taskObserver
                    blockTask = task
                    return task
                }
                return typedOriginalImp(impSelf, Self.selector, impURLRequest, impCompletion)
            }
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)

            swizzler.set(newIMP: newImp, for: method)
        }
    }

    private enum Resume {
        private static let selector = #selector(URLSessionTask.resume)
        private typealias TypedIMP = @convention(c) (URLSessionTask, Selector) -> Void
        private typealias TypedBlockIMP = @convention(block) (URLSessionTask) -> Void

        /// NOTE: RUMM-452
        /// URLSessionTask.resume is not called by its subclasses!
        /// Therefore, we swizzle this method in the subclass.
        /// This is unlike swizzling dataTaskURL/Request: in URLSession base class
        static func swizzleIfNeeded(in task: URLSessionTask) {
            guard let taskClass = object_getClass(task),
                let foundMethod = swizzler.findMethodRecursively(
                    with: selector,
                    in: taskClass
                ) else {
                    userLogger.error("Task \(task), has no class, is passed to \(#function)")
                    return
            }
            // NOTE: RUMM-452 We will probably not need to swizzle tasks every time
            // swizzleIfNonSwizzled lets us perform swizzling in given class if not done before
            swizzler.swizzleIfNonSwizzled(
                foundMethod: foundMethod,
                with: newIMP_resume(for: foundMethod)
            )
        }

        static func newIMP_resume(for foundMethod: MethodSwizzler.FoundMethod) -> IMP {
            let typedOriginalImp: TypedIMP
            typedOriginalImp = swizzler.currentImplementation(of: foundMethod)
            let newImpBlock: TypedBlockIMP = { impSelf in
                impSelf.payload?(.starting)
                return typedOriginalImp(impSelf, selector)
            }
            return imp_implementationWithBlock(newImpBlock)
        }
    }
}

private extension URLSession {
    func urlRequest(with url: URL) -> URLRequest {
        return URLRequest(
            url: url,
            cachePolicy: configuration.requestCachePolicy,
            timeoutInterval: configuration.timeoutIntervalForRequest
        )
    }
}

/// payload is a TaskObserver, executed in task.resume() and completion
private extension URLSessionTask {
    private static var payloadAssociationKey: UInt8 = 0
    var payload: TaskObserver? {
        get { objc_getAssociatedObject(self, &Self.payloadAssociationKey) as? TaskObserver }
        set { objc_setAssociatedObject(self, &Self.payloadAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
