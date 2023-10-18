/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionDataDelegate` callbacks.
internal class URLSessionDataDelegateSwizzler {
    private static var _didReceiveMap: [String: DidReceive?] = [:]
    static var didReceiveMap: [String: DidReceive?] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didReceiveMap
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didReceiveMap = newValue
        }
    }

    private static var lock = NSRecursiveLock()

    static var isBinded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didReceiveMap.isEmpty == false
    }

    static func bindIfNeeded(
        delegateClass: URLSessionDataDelegate.Type,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard isBinded == false else {
            return
        }

        try bind(delegateClass: delegateClass, interceptDidReceive: interceptDidReceive)
    }

    static func bind(
        delegateClass: URLSessionDataDelegate.Type,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data
    ) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        let didReceive = try DidReceive.build(klass: delegateClass)
        let key = MetaTypeExtensions.key(from: delegateClass)

        didReceive.swizzle(intercept: interceptDidReceive)
        didReceiveMap[key] = didReceive
    }

    static func unbind(delegateClass: URLSessionDataDelegate.Type) {
        lock.lock()
        defer { lock.unlock() }

        let key = MetaTypeExtensions.key(from: delegateClass)
        didReceiveMap[key]??.unswizzle()
        didReceiveMap.removeValue(forKey: key)
    }

    static func unbindAll() {
        lock.lock()
        defer { lock.unlock() }

        didReceiveMap.forEach { _, didReceive in
            didReceive?.unswizzle()
        }
        didReceiveMap.removeAll()
    }

    /// Swizzles `urlSession(_:dataTask:didReceive:)` callback.
    /// This callback is called when the response is received.
    /// It is called multiple times for a single request, each time with a new chunk of data.
    class DidReceive: MethodSwizzler<@convention(c) (URLSessionDataDelegate, Selector, URLSession, URLSessionDataTask, Data) -> Void, @convention(block) (URLSessionDataDelegate, URLSession, URLSessionDataTask, Data) -> Void> {
        private static let selector = #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:))

        private let method: FoundMethod

        static func build(klass: URLSessionDataDelegate.Type) throws -> DidReceive {
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
}
