/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSession*` methods.
internal final class URLSessionSwizzler {
    private let lock = NSRecursiveLock()

    private var taskResume: TaskResume?
    private var didFinishCollecting: DidFinishCollecting?
    private var didReceive: DidReceive?

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

    /// Swizzles `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)` method.
    func swizzle(
        delegateClass: AnyClass,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void
    ) throws {
        lock.lock()
        didFinishCollecting = try DidFinishCollecting.build(klass: delegateClass)
        didFinishCollecting?.swizzle(intercept: interceptDidFinishCollecting)
        lock.unlock()
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        taskResume?.unswizzle()
        didFinishCollecting?.unswizzle()
        didReceive?.unswizzle()
        lock.unlock()
    }

    deinit {
        unswizzle()
    }

    /// Swizzles `URLSessionTask.resume()` method.
    class TaskResume: MethodSwizzler<@convention(c) (URLSessionTask, Selector) -> Void, @convention(block) (URLSessionTask) -> Void> {
        private static let selector = #selector(URLSessionTask.resume)

        private let method: Method

        static func build() throws -> TaskResume {
            return try TaskResume(selector: self.selector, klass: URLSessionTask.self)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try dd_class_getInstanceMethod(klass, selector)
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

        private let method: Method

        static func build(klass: AnyClass) throws -> DidReceive {
            return try DidReceive(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try dd_class_getInstanceMethod(klass, selector)
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
                method = try dd_class_getInstanceMethod(klass, selector)
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

        private let method: Method

        static func build(klass: AnyClass) throws -> DidFinishCollecting {
            return try DidFinishCollecting(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try dd_class_getInstanceMethod(klass, selector)
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
                method = try dd_class_getInstanceMethod(klass, selector)
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
}
