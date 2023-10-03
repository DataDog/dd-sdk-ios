/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class URLSessionSwizzler {
    private static var _dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion?
    static var dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _dataTaskWithURLRequestAndCompletion
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _dataTaskWithURLRequestAndCompletion = newValue
        }
    }

    private static var _dataTaskWithURLRequest: DataTaskWithURLRequest?
    static var dataTaskWithURLRequest: DataTaskWithURLRequest? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _dataTaskWithURLRequest
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _dataTaskWithURLRequest = newValue
        }
    }

    private static var lock = NSRecursiveLock()

    static func bindIfNeeded(
        interceptURLRequest: @escaping (URLRequest) -> URLRequest?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard dataTaskWithURLRequestAndCompletion == nil ||
            dataTaskWithURLRequest == nil else {
            return
        }

        try bind(interceptURLRequest: interceptURLRequest)
    }

    static func bind(
        interceptURLRequest: @escaping (URLRequest) -> URLRequest?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        self.dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build()
        dataTaskWithURLRequestAndCompletion?.swizzle(intercept: interceptURLRequest)

        self.dataTaskWithURLRequest = try DataTaskWithURLRequest.build()
        dataTaskWithURLRequest?.swizzle(intercept: interceptURLRequest)
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }
        dataTaskWithURLRequestAndCompletion?.unswizzle()
        dataTaskWithURLRequestAndCompletion = nil

        dataTaskWithURLRequest?.unswizzle()
        dataTaskWithURLRequest = nil
    }

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    class DataTaskWithURLRequestAndCompletion: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask> {
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

        func swizzle(intercept: @escaping (URLRequest) -> URLRequest?) {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request, completionHandler -> URLSessionDataTask in
                    let interceptedRequest = intercept(request) ?? request
                    return previousImplementation(session, Self.selector, interceptedRequest, completionHandler)
                }
            }
        }
    }

    class DataTaskWithURLRequest: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest) -> URLSessionDataTask> {
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

        func swizzle(intercept: @escaping (URLRequest) -> URLRequest?) {
            typealias Signature = @convention(block) (URLSession, URLRequest) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request -> URLSessionDataTask in
                    let interceptedRequest = intercept(request) ?? request
                    return previousImplementation(session, Self.selector, interceptedRequest)
                }
            }
        }
    }
}
