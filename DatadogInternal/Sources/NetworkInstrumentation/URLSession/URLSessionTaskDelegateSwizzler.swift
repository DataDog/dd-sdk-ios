/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionTaskDelegate` callbacks.
internal class URLSessionTaskDelegateSwizzler {
    private let lock: NSLocking
    private var didReceive: DidReceive?
    private var didFinishCollecting: DidFinishCollecting?
    private var didCompleteWithError: DidCompleteWithError?

    init(lock: NSLocking = NSLock()) {
        self.lock = lock
    }

    /// Swizzles  methods:
    /// - `URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)`
    /// - `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)`
    /// - `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`
    func swizzle(
        delegateClass: AnyClass,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data) -> Void,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void,
        interceptDidCompleteWithError: @escaping (URLSession, URLSessionTask, Error?) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        didReceive = try DidReceive.build(klass: delegateClass)
        didFinishCollecting = try DidFinishCollecting.build(klass: delegateClass)
        didCompleteWithError = try DidCompleteWithError.build(klass: delegateClass)
        didReceive?.swizzle(intercept: interceptDidReceive)
        didFinishCollecting?.swizzle(intercept: interceptDidFinishCollecting)
        didCompleteWithError?.swizzle(intercept: interceptDidCompleteWithError)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        didReceive?.unswizzle()
        didFinishCollecting?.unswizzle()
        didCompleteWithError?.unswizzle()
        lock.unlock()
    }

    deinit {
        unswizzle()
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

    class DidCompleteWithError: MethodSwizzler<@convention(c) (URLSessionTaskDelegate, Selector, URLSession, URLSessionTask, Error?) -> Void, @convention(block) (URLSessionTaskDelegate, URLSession, URLSessionTask, Error?) -> Void> {
        private static let selector = #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:))

        private let method: Method

        static func build(klass: AnyClass) throws -> DidCompleteWithError {
            return try DidCompleteWithError(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            do {
                method = try dd_class_getInstanceMethod(klass, selector)
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
                method = try dd_class_getInstanceMethod(klass, selector)
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
