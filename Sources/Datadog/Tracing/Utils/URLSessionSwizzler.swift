/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

// hook into URLSessionTask creation
internal typealias RequestInterceptor = (URLRequest) -> InterceptionResult?

// modifying URLRequest for task creation, observer block to run at resume/completion
internal typealias InterceptionResult = (request: URLRequest, taskPayload: TaskObserver)
internal typealias TaskObserver = (TaskObservationEvent) -> Void
internal enum TaskObservationEvent: Int, Equatable {
    case starting
    case completed
}

internal func swizzleURLSession(interceptor: @escaping RequestInterceptor) throws {
    do {
        try URLSessionSwizzler.DataTask_URL_Completion.swizzle(interceptor: interceptor)
        try URLSessionSwizzler.DataTask_Request_Completion.swizzle(interceptor: interceptor)
    } catch {
        try URLSessionSwizzler.DataTask_URL_Completion.unswizzle()
        try URLSessionSwizzler.DataTask_Request_Completion.unswizzle()
        throw error
    }
}

// MARK: - Private

private enum URLSessionSwizzler {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    static let subjectClass = URLSession.self
    static let swizzler = MethodSwizzler.shared

    enum DataTask_URL_Completion {
        static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask)
        typealias TypedIMP = @convention(c) (URLSession, Selector, URL, @escaping CompletionHandler) -> URLSessionDataTask
        typealias TypedBlockIMP = @convention(block) (URLSession, URL, @escaping CompletionHandler) -> URLSessionDataTask

        static func swizzle(interceptor: @escaping RequestInterceptor) throws {
            try swizzler.swizzle(selector: selector, in: subjectClass, with: newIMP(using: interceptor))
        }

        static func unswizzle() throws {
            try swizzler.unswizzle(selector: selector, in: subjectClass)
        }

        private static func newIMP(using interceptor: @escaping RequestInterceptor) throws -> IMP {
            let sel = selector
            let redirectedSel = DataTask_Request_Completion.selector
            let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)
            let typedRedirectedImp: DataTask_Request_Completion.TypedIMP
            typedRedirectedImp = try swizzler.originalImplementation(of: redirectedSel, in: subjectClass)

            let newImpBlock: TypedBlockIMP = { impSelf, impURL, impCompletion -> URLSessionDataTask in
                if let interceptionResult = interceptor(impSelf.urlRequest(with: impURL)) {
                    weak var blockTask: URLSessionDataTask? = nil
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }
                    let task = typedRedirectedImp(impSelf, sel, interceptionResult.request, modifiedCompletion)
                    // TODO: RUMM-452 report error?
                    try? Resume.swizzle(in: task)
                    task.payload = interceptionResult.taskPayload
                    blockTask = task
                    return task
                }

                return typedOriginalImp(impSelf, sel, impURL, impCompletion)
            }
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)
            return newImp
        }
    }

    enum DataTask_Request_Completion {
        static let selector = #selector(URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask)
        typealias TypedIMP = @convention(c) (URLSession, Selector, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        typealias TypedBlockIMP = @convention(block) (URLSession, URLRequest, @escaping CompletionHandler) -> URLSessionDataTask

        static func swizzle(interceptor: @escaping RequestInterceptor) throws {
            try swizzler.swizzle(selector: selector, in: subjectClass, with: newIMP(using: interceptor))
        }

        static func unswizzle() throws {
            try swizzler.unswizzle(selector: selector, in: subjectClass)
        }

        private static func newIMP(using interceptor: @escaping RequestInterceptor) throws -> IMP {
            let sel = selector
            let typedOriginalImp: TypedIMP = try swizzler.currentImplementation(of: sel, in: subjectClass)

            let newImpBlock: TypedBlockIMP = { impSelf, impURLRequest, impCompletion -> URLSessionDataTask in
                if let interceptionResult = interceptor(impURLRequest) {
                    weak var blockTask: URLSessionDataTask? = nil

                    // swizzled completion handler
                    let modifiedCompletion: CompletionHandler = { origData, origResponse, origError in
                        // unswizzled completion handler
                        impCompletion(origData, origResponse, origError)
                        blockTask?.payload?(.completed)
                    }

                    let task = typedOriginalImp(impSelf, sel, interceptionResult.request, modifiedCompletion)
                    // TODO: RUMM-452 report error?
                    try? Resume.swizzle(in: task)
                    task.payload = interceptionResult.taskPayload
                    blockTask = task
                    return task
                }
                return typedOriginalImp(impSelf, sel, impURLRequest, impCompletion)
            }
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)
            return newImp
        }
    }

    enum Resume {
        static let selector = #selector(URLSessionTask.resume)
        typealias TypedIMP = @convention(c) (URLSessionTask, Selector) -> Void
        typealias TypedBlockIMP = @convention(block) (URLSessionTask) -> Void

        static func swizzle(in task: URLSessionTask) throws {
            guard let taskClass = object_getClass(task) else {
                // TODO: RUMM-452 report error?
                // InternalError(description: "Task \(task), has no class, is passed to \(#function)")
                return
            }
            // NOTE: RUMM-452 We will probably not need to swizzle tasks every time
            // swizzleIfNonSwizzled lets us perform swizzling in given class if not done before
            try swizzler.swizzleIfNonSwizzled(
                selector: selector,
                in: taskClass,
                with: newIMP_resume(for: taskClass)
            )
        }

        private static func newIMP_resume(for klass: AnyClass) throws -> IMP {
            let typedOriginalImp: TypedIMP
            typedOriginalImp = try swizzler.currentImplementation(of: selector, in: klass)
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

// payload is executed in task.resume() and completion
private extension URLSessionTask {
    private static var payloadAssociationKey: UInt8 = 0
    var payload: TaskObserver? {
        get { objc_getAssociatedObject(self, &Self.payloadAssociationKey) as? TaskObserver }
        set { objc_setAssociatedObject(self, &Self.payloadAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
