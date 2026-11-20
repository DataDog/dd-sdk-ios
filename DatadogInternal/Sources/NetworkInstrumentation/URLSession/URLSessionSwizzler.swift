/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSession*` methods.
internal final class URLSessionSwizzler {
    private let lock: NSLocking
    private var dataTaskURLRequestCompletionHandler: DataTaskURLRequestCompletionHandler?
    private var dataTaskURLCompletionHandler: DataTaskURLCompletionHandler?
    private var asyncDataTaskURLRequest: AsyncDataTaskCompletionHandler?
    private var asyncDataTaskURL: AsyncDataTaskCompletionHandler?

    init(lock: NSLocking = NSLock()) {
        self.lock = lock
    }

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` methods (with `URL` and `URLRequest`).
    func swizzle(
        interceptCompletionHandler: @escaping (URLSessionTask, Data?, Error?) -> Void,
        didReceive: @escaping (URLSessionTask, Data) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        dataTaskURLRequestCompletionHandler = try DataTaskURLRequestCompletionHandler.build()
        dataTaskURLRequestCompletionHandler?.swizzle(
            interceptCompletion: interceptCompletionHandler,
            didReceive: didReceive
        )

        dataTaskURLCompletionHandler = try DataTaskURLCompletionHandler.build()
        dataTaskURLCompletionHandler?.swizzle(
            interceptCompletion: interceptCompletionHandler,
            didReceive: didReceive
        )

        // Private selectors used by `URLSession.data(for:delegate:)` and `data(from:delegate:)`.
        // Skipped silently when unavailable on the running OS.
        asyncDataTaskURLRequest = AsyncDataTaskCompletionHandler.build(selectorName: "_dataTaskWithRequest:delegate:completionHandler:")
        asyncDataTaskURLRequest?.swizzle(interceptCompletion: interceptCompletionHandler, didReceive: didReceive)

        asyncDataTaskURL = AsyncDataTaskCompletionHandler.build(selectorName: "_dataTaskWithURL:delegate:completionHandler:")
        asyncDataTaskURL?.swizzle(interceptCompletion: interceptCompletionHandler, didReceive: didReceive)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        dataTaskURLRequestCompletionHandler?.unswizzle()
        dataTaskURLCompletionHandler?.unswizzle()
        asyncDataTaskURLRequest?.unswizzle()
        asyncDataTaskURL?.unswizzle()
        lock.unlock()
    }

    deinit {
        unswizzle()
    }

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` (with `URLRequest`) method.
    class DataTaskURLRequestCompletionHandler: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        )

        private let method: Method

        static func build() throws -> DataTaskURLRequestCompletionHandler {
            return try DataTaskURLRequestCompletionHandler(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try dd_class_getInstanceMethod(klass, selector)
            super.init()
        }

        func swizzle(
            interceptCompletion: @escaping (URLSessionTask, Data?, Error?) -> Void,
            didReceive: @escaping (URLSessionTask, Data) -> Void
        ) {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request, completionHandler -> URLSessionDataTask in
                    guard let completionHandler = completionHandler else {
                        // The `completionHandler` can be `nil` when `[session dataTaskWithURL:completionHandler:]` is called
                        // in Objective-C with explicitly passing `nil` as the `completionHandler` (it produces a warning,
                        // but compiles).
                        return previousImplementation(session, Self.selector, request, completionHandler)
                    }

                    var _task: URLSessionDataTask?
                    let task = previousImplementation(session, Self.selector, request) { data, response, error in
                        if let task = _task, let data = data {
                            didReceive(task, data)
                        }

                        if let task = _task { // sanity check, should always succeed
                            interceptCompletion(task, data, error)
                        }

                        completionHandler(data, response, error)
                    }
                    _task = task
                    _task?.dd.hasCompletion = true
                    return task
                }
            }
        }
    }

    /// Swizzles a private `NSURLSession` selector of shape `_dataTaskWith<URL|Request>:delegate:completionHandler:`.
    ///
    /// Swift async `URLSession.data(for:delegate:)` and `data(from:delegate:)` create their task through these
    /// selectors (observed on iOS 26 / macOS 27), bypassing the public `dataTask(with:completionHandler:)`.
    /// The first argument (`URL` or `URLRequest`) and the delegate are passed through as opaque objects.
    class AsyncDataTaskCompletionHandler: MethodSwizzler<@convention(c) (URLSession, Selector, AnyObject, AnyObject?, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, AnyObject, AnyObject?, CompletionHandler?) -> URLSessionDataTask> {
        private let selector: Selector
        private let method: Method

        /// Returns `nil` if the selector does not exist or has an unexpected signature.
        static func build(selectorName: String, klass: AnyClass = URLSession.self) -> AsyncDataTaskCompletionHandler? {
            let selector = NSSelectorFromString(selectorName)
            guard let method = class_getInstanceMethod(klass, selector),
                  let encoding = method_getTypeEncoding(method),
                  Self.hasExpectedSignature(String(cString: encoding)) else {
                return nil
            }
            return AsyncDataTaskCompletionHandler(selector: selector, method: method)
        }

        /// Expects `(id)self, SEL, id, id, block -> id`, e.g. `@40@0:8@16@24@?32`.
        private static func hasExpectedSignature(_ encoding: String) -> Bool {
            let types = encoding.filter { !$0.isNumber }
            return types == "@@:@@@?"
        }

        private init(selector: Selector, method: Method) {
            self.selector = selector
            self.method = method
            super.init()
        }

        func swizzle(
            interceptCompletion: @escaping (URLSessionTask, Data?, Error?) -> Void,
            didReceive: @escaping (URLSessionTask, Data) -> Void
        ) {
            typealias Signature = @convention(block) (URLSession, AnyObject, AnyObject?, CompletionHandler?) -> URLSessionDataTask
            let selector = self.selector
            swizzle(method) { previousImplementation -> Signature in
                return { session, urlOrRequest, delegate, completionHandler -> URLSessionDataTask in
                    guard let completionHandler = completionHandler else {
                        return previousImplementation(session, selector, urlOrRequest, delegate, completionHandler)
                    }

                    var _task: URLSessionDataTask?
                    let task = previousImplementation(session, selector, urlOrRequest, delegate) { data, response, error in
                        if let task = _task, let data = data {
                            didReceive(task, data)
                        }

                        if let task = _task { // sanity check, should always succeed
                            interceptCompletion(task, data, error)
                        }

                        completionHandler(data, response, error)
                    }
                    _task = task
                    _task?.dd.hasCompletion = true
                    return task
                }
            }
        }
    }

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` (with `URL`) method.
    class DataTaskURLCompletionHandler: MethodSwizzler<@convention(c) (URLSession, Selector, URL, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask
        )

        private let method: Method

        static func build() throws -> DataTaskURLCompletionHandler {
            return try DataTaskURLCompletionHandler(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try dd_class_getInstanceMethod(klass, selector)
            super.init()
        }

        func swizzle(
            interceptCompletion: @escaping (URLSessionTask, Data?, Error?) -> Void,
            didReceive: @escaping (URLSessionTask, Data) -> Void
        ) {
            typealias Signature = @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, url, completionHandler -> URLSessionDataTask in
                    guard let completionHandler = completionHandler else {
                        // The `completionHandler` can be `nil` when `[session dataTaskWithURL:completionHandler:]` is called
                        // in Objective-C with explicitly passing `nil` as the `completionHandler` (it produces a warning,
                        // but compiles).
                        return previousImplementation(session, Self.selector, url, completionHandler)
                    }

                    var _task: URLSessionDataTask?
                    let task = previousImplementation(session, Self.selector, url) { data, response, error in
                        if let task = _task, let data = data {
                            didReceive(task, data)
                        }

                        if let task = _task { // sanity check, should always succeed
                            interceptCompletion(task, data, error)
                        }

                        completionHandler(data, response, error)
                    }
                    _task = task
                    _task?.dd.hasCompletion = true
                    return task
                }
            }
        }
    }
}
