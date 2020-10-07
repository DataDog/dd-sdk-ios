/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class URLSessionSwizzler {
    /// `URLSession.dataTask(with:completionHandler:)` (for `URLRequest`) swizzling.
    let dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion
    /// `URLSession.dataTask(with:)` (for `URLRequest`) swizzling.
    let dataTaskWithURLRequest: DataTaskWithURLRequest

    /// `URLSession.dataTask(with:completionHandler:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
    let dataTaskWithURLAndCompletion: DataTaskWithURLAndCompletion?
    /// `URLSession.dataTask(with:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
    let dataTaskWithURL: DataTaskWithURL?

    private let interceptor: URLSessionInterceptorType

    init(interceptor: URLSessionInterceptorType) throws {
        if #available(iOS 13.0, *) {
            self.dataTaskWithURLAndCompletion = try DataTaskWithURLAndCompletion(interceptor: interceptor)
            self.dataTaskWithURL = try DataTaskWithURL(interceptor: interceptor)
        } else {
            // Prior to iOS 13.0 we do not apply following swizzlings, as those methods call
            // the `URLSession.dataTask(with:completionHandler:)` internally which is managed
            // by the `DataTaskWithURLRequestAndCompletion` swizzling.
            self.dataTaskWithURLAndCompletion = nil
            self.dataTaskWithURL = nil
        }
        self.dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion(interceptor: interceptor)
        self.dataTaskWithURLRequest = try DataTaskWithURLRequest(interceptor: interceptor)
        self.interceptor = interceptor
    }

    func swizzle() {
        dataTaskWithURLRequestAndCompletion.swizzle()
        dataTaskWithURLAndCompletion?.swizzle()
        dataTaskWithURLRequest.swizzle()
        dataTaskWithURL?.swizzle()
    }

    // MARK: - Swizzlings

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URLRequest`.
    class DataTaskWithURLRequestAndCompletion: MethodSwizzler<
        @convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask,
        @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
    > {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        )

        private let method: FoundMethod
        private let interceptor: URLSessionInterceptorType

        init(interceptor: URLSessionInterceptorType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.interceptor = interceptor
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { [weak self] session, urlRequest, completionHandler -> URLSessionDataTask in
                    let task: URLSessionDataTask

                    if completionHandler != nil {
                        var taskReference: URLSessionDataTask?

                        let newCompletionHandler: CompletionHandler = { data, response, error in
                            if let task = taskReference { // sanity check, should always succeed
                                self?.interceptor.taskCompleted(urlSession: session, task: task, error: error)
                            }
                            completionHandler?(data, response, error)
                        }

                        let newRequest = self?.interceptor.modify(request: urlRequest) ?? urlRequest

                        task = previousImplementation(session, Self.selector, newRequest, newCompletionHandler)
                        taskReference = task
                    } else {
                        // The `completionHandler` can be `nil` in two cases:
                        // - on iOS 11 or 12, where `dataTask(with:)` (for `URL` and `URLRequest`) calls
                        //   the `dataTask(with:completionHandler:)` (for `URLRequest`) internally by nullifying the completion block.
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
                        task = previousImplementation(session, Self.selector, urlRequest, completionHandler)
                    }

                    self?.interceptor.taskCreated(urlSession: session, task: task)

                    return task
                }
            }
        }
    }

    /// Swizzles the `URLSession.dataTask(with:completionHandler:)` for `URL`.
    class DataTaskWithURLAndCompletion: MethodSwizzler<
        @convention(c) (URLSession, Selector, URL, CompletionHandler?) -> URLSessionDataTask,
        @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
    > {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URL, @escaping CompletionHandler) -> URLSessionDataTask
        )

        private let method: FoundMethod
        private let interceptor: URLSessionInterceptorType

        init(interceptor: URLSessionInterceptorType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.interceptor = interceptor
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { [weak self] session, url, completionHandler -> URLSessionDataTask in
                    let task: URLSessionDataTask

                    if completionHandler != nil {
                        var taskReference: URLSessionDataTask?

                        let newCompletionHandler: CompletionHandler = { data, response, error in
                            if let task = taskReference { // sanity check, should always succeed
                                self?.interceptor.taskCompleted(urlSession: session, task: task, error: error)
                            }
                            completionHandler?(data, response, error)
                        }

                        task = previousImplementation(session, Self.selector, url, newCompletionHandler)
                        taskReference = task
                    } else {
                        // The `completionHandler` can be `nil` in one case:
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
                        task = previousImplementation(session, Self.selector, url, completionHandler)
                    }

                    self?.interceptor.taskCreated(urlSession: session, task: task)

                    return task
                }
            }
        }
    }

    /// Swizzles the `URLSession.dataTask(with:)` for `URLRequest`.
    class DataTaskWithURLRequest: MethodSwizzler<
        @convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask,
        @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
    > {
        private static let selector = #selector(
            URLSession.dataTask(with:) as (URLSession) -> (URLRequest) -> URLSessionDataTask
        )

        private let method: FoundMethod
        private let interceptor: URLSessionInterceptorType

        init(interceptor: URLSessionInterceptorType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.interceptor = interceptor
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { [weak self] session, urlRequest -> URLSessionDataTask in
                    let newRequest = self?.interceptor.modify(request: urlRequest) ?? urlRequest
                    let task = previousImplementation(session, Self.selector, newRequest)
                    if #available(iOS 13.0, *) {
                        // Prior to iOS 13.0, `dataTask(with:)` (for `URLRequest`) calls the
                        // the `dataTask(with:completionHandler:)` (for `URLRequest`) internally,
                        // so the task creation will be notified from `dataTaskWithURLRequestAndCompletion` swizzling.
                        self?.interceptor.taskCreated(urlSession: session, task: task)
                    }
                    return task
                }
            }
        }
    }

    /// Swizzles the `URLSession.dataTask(with:)` for `URL`.
    class DataTaskWithURL: MethodSwizzler<
        @convention(c) (URLSession, Selector, URL) -> URLSessionDataTask,
        @convention(block) (URLSession, URL) -> URLSessionDataTask
    > {
        private static let selector = #selector(
            URLSession.dataTask(with:) as (URLSession) -> (URL) -> URLSessionDataTask
        )

        private let method: FoundMethod
        private let interceptor: URLSessionInterceptorType

        init(interceptor: URLSessionInterceptorType) throws {
            self.method = try Self.findMethod(with: Self.selector, in: URLSession.self)
            self.interceptor = interceptor
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URL) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { [weak self] session, url -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, url)
                    self?.interceptor.taskCreated(urlSession: session, task: task)
                    return task
                }
            }
        }
    }
}
