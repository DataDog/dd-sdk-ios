/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionTaskDelegate` callbacks.
internal class URLSessionTaskDelegateSwizzler {
    private static var _didFinishCollectingMap: [String: DidFinishCollecting?] = [:]
    static var didFinishCollectingMap: [String: DidFinishCollecting?] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didFinishCollectingMap
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didFinishCollectingMap = newValue
        }
    }
    private static var lock = NSRecursiveLock()

    static var isBinded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFinishCollectingMap.isEmpty == false
    }

    static func bindIfNeeded(
        delegateClass: AnyClass,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard isBinded == false else {
            return
        }

        try bind(
            delegateClass: delegateClass,
            interceptDidFinishCollecting: interceptDidFinishCollecting
        )
    }

    static func bind(
        delegateClass: AnyClass,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let didFinishCollecting = try DidFinishCollecting.build(klass: delegateClass)
        let key = MetaTypeExtensions.key(from: delegateClass)

        didFinishCollecting.swizzle(intercept: interceptDidFinishCollecting)
        didFinishCollectingMap[key] = didFinishCollecting
    }

    static func unbind(delegateClass: AnyClass) {
        lock.lock()
        defer { lock.unlock() }

        let key = MetaTypeExtensions.key(from: delegateClass)
        didFinishCollectingMap[key]??.unswizzle()
        didFinishCollectingMap[key] = nil
    }

    static func unbindAll() {
        lock.lock()
        defer { lock.unlock() }

        didFinishCollectingMap.forEach { _, didFinishCollecting in
            didFinishCollecting?.unswizzle()
        }

        didFinishCollectingMap.removeAll()
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
}
