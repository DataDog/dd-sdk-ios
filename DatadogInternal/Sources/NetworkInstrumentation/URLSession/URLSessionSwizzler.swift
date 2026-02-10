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

        if #available(iOS 13.0, *) {
            // Prior to iOS 13.0 the `URLSession.dataTask(with:url, completionHandler:handler)` makes an internal
            // call to `URLSession.dataTask(with:request, completionHandler:handler)`. To avoid duplicated call
            // to the callback, we don't apply below swizzling prior to iOS 13.
            dataTaskURLCompletionHandler = try DataTaskURLCompletionHandler.build()
            dataTaskURLCompletionHandler?.swizzle(
                interceptCompletion: interceptCompletionHandler,
                didReceive: didReceive
            )
        }
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        dataTaskURLRequestCompletionHandler?.unswizzle()
        dataTaskURLCompletionHandler?.unswizzle()
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
                        // The `completionHandler` can be `nil` in two cases:
                        // - on iOS 11 or 12, where `dataTask(with:)` (for `URL` and `URLRequest`) calls
                        //   the `dataTask(with:completionHandler:)` (for `URLRequest`) internally by nullifying the completion block.
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
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
                        // The `completionHandler` can be `nil` in two cases:
                        // - on iOS 11 or 12, where `dataTask(with:)` (for `URL` and `URLRequest`) calls
                        //   the `dataTask(with:completionHandler:)` (for `URLRequest`) internally by nullifying the completion block.
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
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
