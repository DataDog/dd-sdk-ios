/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionDataDelegate` callbacks.
internal class URLSessionDataDelegateSwizzler {
    private let lock: NSLocking
    private var didReceive: DidReceive?

    init(lock: NSLocking = NSLock()) {
        self.lock = lock
    }

    /// Swizzles  methods:
    /// - `URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)`
    func swizzle(
        delegateClass: URLSessionDataDelegate.Type,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        didReceive = try DidReceive.build(klass: delegateClass)
        didReceive?.swizzle(intercept: interceptDidReceive)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        didReceive?.unswizzle()
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
}
