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

    private static var lock = NSRecursiveLock()

    static var isBinded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dataTaskWithURLRequestAndCompletion != nil
    }

    static func bindIfNeeded(
        interceptURLRequest: @escaping (URLRequest) -> URLRequest?,
        interceptTask: @escaping (URLSessionTask) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard dataTaskWithURLRequestAndCompletion == nil else {
            return
        }

        try bind(interceptURLRequest: interceptURLRequest, interceptTask: interceptTask)
    }

    static func bind(
        interceptURLRequest: @escaping (URLRequest) -> URLRequest?,
        interceptTask: @escaping (URLSessionTask) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        self.dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build()
        dataTaskWithURLRequestAndCompletion?.swizzle(interceptRequest: interceptURLRequest, interceptTask: interceptTask)
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }
        dataTaskWithURLRequestAndCompletion?.unswizzle()
        dataTaskWithURLRequestAndCompletion = nil
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

        func swizzle(
            interceptRequest: @escaping (URLRequest) -> URLRequest?,
            interceptTask: @escaping (URLSessionTask) -> Void
        ) {
            typealias Signature = @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask
            swizzle(method) { previousImplementation -> Signature in
                return { session, request, completionHandler -> URLSessionDataTask in
                    let interceptedRequest = interceptRequest(request) ?? request
                    let task = previousImplementation(session, Self.selector, interceptedRequest, completionHandler)
                    interceptTask(task)
                    return task
                }
            }
        }
    }
}
