/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class URLSessionSwizzler {
    /// Counts of bindings of the URL swizzler.
    ///
    /// This value will increment for each call to the `bind()` method.
    /// Calling `unbind()` will decrement the count, when reaching zero, the swizzler is disabled.
    internal private(set) static var bindingsCount: UInt = 0
    /// The binding lock.
    private static var lock = NSLock()
    /// `URLSession.dataTask(with:completionHandler:)` (for `URLRequest`) swizzling.
    internal private(set) static var dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion?
    /// `URLSession.dataTask(with:)` (for `URLRequest`) swizzling.
    internal private(set) static var dataTaskWithURLRequest: DataTaskWithURLRequest?
    /// `URLSession.dataTask(with:completionHandler:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
    internal private(set) static var dataTaskWithURLAndCompletion: DataTaskWithURLAndCompletion?
    /// `URLSession.dataTask(with:)` (for `URL`) swizzling. Only applied on iOS 13 and above.
    internal private(set) static var dataTaskWithURL: DataTaskWithURL?

    static func bind() throws {
        lock.lock()
        defer { lock.unlock() }

        guard bindingsCount == 0 else {
            return bindingsCount += 1
        }

        if #available(iOS 13.0, *) {
            // Prior to iOS 13.0 we do not apply following swizzlings, as those methods call
            // the `URLSession.dataTask(with:completionHandler:)` internally which is managed
            // by the `DataTaskWithURLRequestAndCompletion` swizzling.
            dataTaskWithURLAndCompletion = try DataTaskWithURLAndCompletion.build()
            dataTaskWithURL = try DataTaskWithURL.build()
        }

        dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build()
        dataTaskWithURLRequest = try DataTaskWithURLRequest.build()

        dataTaskWithURLRequestAndCompletion?.swizzle()
        dataTaskWithURLAndCompletion?.swizzle()
        dataTaskWithURLRequest?.swizzle()
        dataTaskWithURL?.swizzle()

        bindingsCount += 1
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }

        if bindingsCount == 0 {
            return
        }

        if bindingsCount > 1 {
            return bindingsCount -= 1
        }

        dataTaskWithURLRequestAndCompletion?.unswizzle()
        dataTaskWithURLRequest?.unswizzle()
        dataTaskWithURLAndCompletion?.unswizzle()
        dataTaskWithURL?.unswizzle()

        dataTaskWithURLRequestAndCompletion = nil
        dataTaskWithURLRequest = nil
        dataTaskWithURLAndCompletion = nil
        dataTaskWithURL = nil

        bindingsCount -= 1
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

        static func build() throws -> DataTaskWithURLRequestAndCompletion {
            return try DataTaskWithURLRequestAndCompletion(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request, completionHandler -> URLSessionDataTask in
                    guard
                        let delegate = (session.delegate as? __URLSessionDelegateProviding)?.ddURLSessionDelegate,
                        let interceptor = delegate.interceptor
                    else {
                        return previousImplementation(session, Self.selector, request, completionHandler)
                    }

                    guard let completionHandler = completionHandler else {
                        // The `completionHandler` can be `nil` in two cases:
                        // - on iOS 11 or 12, where `dataTask(with:)` (for `URL` and `URLRequest`) calls
                        //   the `dataTask(with:completionHandler:)` (for `URLRequest`) internally by nullifying the completion block.
                        // - when `[session dataTaskWithURL:completionHandler:]` is called in Objective-C with explicitly passing
                        //   `nil` as the `completionHandler` (it produces a warning, but compiles).
                        let task = previousImplementation(session, Self.selector, request, completionHandler)
                        interceptor.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
                        return task
                    }

                    var _task: URLSessionDataTask?
                    let request = interceptor.intercept(request: request, additionalFirstPartyHosts: delegate.firstPartyHosts)
                    let task = previousImplementation(session, Self.selector, request) { data, response, error in
                        completionHandler(data, response, error)

                        if let task = _task { // sanity check, should always succeed
                            data.map { interceptor.task(task, didReceive: $0) }
                            interceptor.task(task, didCompleteWithError: error)
                        }
                    }

                    _task = task
                    interceptor.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
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

        static func build() throws -> DataTaskWithURLAndCompletion {
            return try DataTaskWithURLAndCompletion(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URL, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, url, completionHandler -> URLSessionDataTask in
                    guard
                        let delegate = (session.delegate as? __URLSessionDelegateProviding)?.ddURLSessionDelegate,
                        let interceptor = delegate.interceptor
                    else {
                        return previousImplementation(session, Self.selector, url, completionHandler)
                    }

                    guard let completionHandler = completionHandler else {
                        let task = previousImplementation(session, Self.selector, url, completionHandler)
                        interceptor.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
                        return task
                    }

                    var _task: URLSessionDataTask?
                    let task = previousImplementation(session, Self.selector, url) { data, response, error in
                        completionHandler(data, response, error)

                        if let task = _task { // sanity check, should always succeed
                            data.map { interceptor.task(task, didReceive: $0) }
                            interceptor.task(task, didCompleteWithError: error)
                        }
                    }

                    _task = task
                    interceptor.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
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

        static func build() throws -> DataTaskWithURLRequest {
            return try DataTaskWithURLRequest(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request -> URLSessionDataTask in
                    guard let delegate = (session.delegate as? __URLSessionDelegateProviding)?.ddURLSessionDelegate else {
                        return previousImplementation(session, Self.selector, request)
                    }

                    let request = delegate.interceptor?.intercept(request: request, additionalFirstPartyHosts: delegate.firstPartyHosts) ?? request
                    let task = previousImplementation(session, Self.selector, request)
                    if #available(iOS 13.0, *) {
                        // Prior to iOS 13.0, `dataTask(with:)` (for `URLRequest`) calls the
                        // the `dataTask(with:completionHandler:)` (for `URLRequest`) internally,
                        // so the task creation will be notified from `dataTaskWithURLRequestAndCompletion` swizzling.
                        delegate.interceptor?.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
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

        static func build() throws -> DataTaskWithURL {
            return try DataTaskWithURL(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle() {
            typealias Signature = @convention(block) (URLSession, URL) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, url -> URLSessionDataTask in
                    let task = previousImplementation(session, Self.selector, url)
                    if let delegate = (session.delegate as? __URLSessionDelegateProviding)?.ddURLSessionDelegate {
                        delegate.interceptor?.intercept(task: task, additionalFirstPartyHosts: delegate.firstPartyHosts)
                    }
                    return task
                }
            }
        }
    }
}
