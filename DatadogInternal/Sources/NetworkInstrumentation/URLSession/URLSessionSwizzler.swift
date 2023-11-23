/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSession*` methods.
internal final class URLSessionSwizzler {
    private let lock = NSRecursiveLock()

    private var dataTaskWithURLRequestAndCompletion: DataTaskWithURLRequestAndCompletion?
    private var taskResume: TaskResume?
    private var didFinishCollecting: DidFinishCollecting?
    private var didReceive: DidReceive?
    private var didCompleteWithError: DidCompleteWithError?

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` method.
    func swizzle(
        interceptRequest: @escaping (URLRequest) -> URLRequest?,
        interceptTask: @escaping (URLSessionTask) -> Void
    ) throws {
        lock.lock()
        dataTaskWithURLRequestAndCompletion = try DataTaskWithURLRequestAndCompletion.build()
        dataTaskWithURLRequestAndCompletion?.swizzle(interceptRequest: interceptRequest, interceptTask: interceptTask)
        lock.unlock()
    }

    /// Swizzles `URLSessionTask.resume()` method.
    func swizzle(
        interceptResume: @escaping (URLSessionTask) -> Void
    ) throws {
        lock.lock()
        taskResume = try TaskResume.build()
        taskResume?.swizzle(intercept: interceptResume)
        lock.unlock()
    }

    /// Swizzles  `URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)` method.
    func swizzle(
        delegateClass: AnyClass,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data) -> Void
    ) throws {
        lock.lock()
        didReceive = try DidReceive.build(klass: delegateClass)
        didReceive?.swizzle(intercept: interceptDidReceive)
        lock.unlock()
    }

    /// Swizzles `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)` and
    /// `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)` methods.
    func swizzle(
        delegateClass: AnyClass,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void,
        interceptDidCompleteWithError: @escaping (URLSession, URLSessionTask, Error?) -> Void
    ) throws {
        lock.lock()
        didFinishCollecting = try DidFinishCollecting.build(klass: delegateClass)
        didCompleteWithError = try DidCompleteWithError.build(klass: delegateClass)
        didFinishCollecting?.swizzle(intercept: interceptDidFinishCollecting)
        didCompleteWithError?.swizzle(intercept: interceptDidCompleteWithError)
        lock.unlock()
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        dataTaskWithURLRequestAndCompletion?.unswizzle()
        taskResume?.unswizzle()
        didFinishCollecting?.unswizzle()
        didCompleteWithError?.unswizzle()
        didReceive?.unswizzle()
        lock.unlock()
    }

    deinit {
        unswizzle()
    }

    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` method.
    class DataTaskWithURLRequestAndCompletion: MethodSwizzler<@convention(c) (URLSession, Selector, URLRequest, CompletionHandler?) -> URLSessionDataTask, @convention(block) (URLSession, URLRequest, CompletionHandler?) -> URLSessionDataTask> {
        private static let selector = #selector(
            URLSession.dataTask(with:completionHandler:) as (URLSession) -> (URLRequest, @escaping CompletionHandler) -> URLSessionDataTask
        )

        private let method: Method

        static func build() throws -> DataTaskWithURLRequestAndCompletion {
            return try DataTaskWithURLRequestAndCompletion(
                selector: self.selector,
                klass: URLSession.self
            )
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try dd_class_getInstanceMethod(klass, selector)
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

    /// Swizzles `URLSessionTask.resume()` method.
    class TaskResume: MethodSwizzler<@convention(c) (URLSessionTask, Selector) -> Void, @convention(block) (URLSessionTask) -> Void> {
        private static let selector = #selector(URLSessionTask.resume)

        private let method: FoundMethod

        static func build() throws -> TaskResume {
            return try TaskResume(selector: self.selector, klass: URLSessionTask.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try Self.findMethod(with: selector, in: klass)
            super.init()
        }

        func swizzle(intercept: @escaping (URLSessionTask) -> Void) {
            typealias Signature = @convention(block) (URLSessionTask) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { task in
                    intercept(task)
                    previousImplementation(task, Self.selector)
                }
            }
        }
    }

    /// Swizzles `urlSession(_:dataTask:didReceive:)` callback.
    /// This callback is called when the response is received.
    /// It is called multiple times for a single request, each time with a new chunk of data.
    class DidReceive: MethodSwizzler<@convention(c) (URLSessionDataDelegate, Selector, URLSession, URLSessionDataTask, Data) -> Void, @convention(block) (URLSessionDataDelegate, URLSession, URLSessionDataTask, Data) -> Void> {
        private static let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:))

        private let method: FoundMethod

        static func build(klass: AnyClass) throws -> DidReceive {
            return try DidReceive(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try Self.findMethod(with: selector, in: klass)
            } catch {
                // URLSessionDataDelegate doesn't implement the selector, so we inject it and swizzle it
                let block: @convention(block) (URLSessionDataDelegate, URLSession, URLSessionDataTask, Data) -> Void = { delegate, session, task, data in
                }
                let imp = imp_implementationWithBlock(block)
                /*
                v@:@@@ means:
                v - return type is void
                @ - self
                : - selector
                @ - first argument is an object
                @ - second argument is an object
                @ - third argument is an object
                */
                class_addMethod(klass, selector, imp, "v@:@@@")
                method = try Self.findMethod(with: selector, in: klass)
            }

            super.init()
        }

        func swizzle(intercept: @escaping (URLSession, URLSessionDataTask, Data) -> Void) {
            typealias Signature = @convention(block) (URLSessionDataDelegate, URLSession, URLSessionDataTask, Data) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { delegate, session, task, data in
                    intercept(session, task, data)
                    return previousImplementation(delegate, Self.selector, session, task, data)
                }
            }
        }
    }

    /// Swizzles `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)` method.
    class DidFinishCollecting: MethodSwizzler<@convention(c) (URLSessionTaskDelegate, Selector, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void, @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void> {
        private static let selector = #selector(URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:))

        private let method: FoundMethod

        static func build(klass: AnyClass) throws -> DidFinishCollecting {
            return try DidFinishCollecting(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try Self.findMethod(with: selector, in: klass)
            } catch {
                // URLSessionTaskDelegate doesn't implement the selector, so we inject it and swizzle it
                let block: @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void = { delegate, session, task, metrics in
                }
                let imp = imp_implementationWithBlock(block)
                /*
                v@:@@@ means:
                v - return type is void
                @ - self
                : - selector
                @ - first argument is an object
                @ - second argument is an object
                @ - third argument is an object
                */
                class_addMethod(klass, selector, imp, "v@:@@@")
                method = try Self.findMethod(with: selector, in: klass)
            }

            super.init()
        }

        func swizzle(intercept: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void) {
            typealias Signature = @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { delegate, session, task, metrics in
                    intercept(session, task, metrics)
                    return previousImplementation(delegate, Self.selector, session, task, metrics)
                }
            }
        }
    }

    class DidCompleteWithError: MethodSwizzler<@convention(c) (URLSessionTaskDelegate, Selector, URLSession, URLSessionTask, Error?) -> Void, @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, Error?) -> Void> {
        private static let selector = #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:))

        private let method: FoundMethod

        static func build(klass: AnyClass) throws -> DidCompleteWithError {
            return try DidCompleteWithError(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try Self.findMethod(with: selector, in: klass)
            } catch {
                // URLSessionTaskDelegate doesn't implement the selector, so we inject it and swizzle it
                let block: @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, Error?) -> Void = { delegate, session, task, error in
                }
                let imp = imp_implementationWithBlock(block)
                /*
                v@:@@@ means:
                v - return type is void
                @ - self
                : - selector
                @ - first argument is an object
                @ - second argument is an object
                @ - third argument is an object
                */
                class_addMethod(klass, selector, imp, "v@:@@@")
                method = try Self.findMethod(with: selector, in: klass)
            }

            super.init()
        }

        func swizzle(intercept: @escaping (URLSession, URLSessionTask, Error?) -> Void) {
            typealias Signature = @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, Error?) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { delegate, session, task, error in
                    intercept(session, task, error)
                    return previousImplementation(delegate, Self.selector, session, task, error)
                }
            }
        }
    }
}
