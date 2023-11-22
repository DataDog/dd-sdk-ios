/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionTask` methods.
internal class URLSessionTaskSwizzler {
    private static var _resume: Resume?
    static var resume: Resume? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _resume
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _resume = newValue
        }
    }

    private static var lock = NSRecursiveLock()

    static var isBinded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resume != nil
    }

    static func bindIfNeeded(interceptResume: @escaping (URLSessionTask) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        guard resume == nil else {
            return
        }

        try bind(interceptResume: interceptResume)
    }

    static func bind(interceptResume: @escaping (URLSessionTask) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        self.resume = try Resume.build()

        resume?.swizzle(intercept: interceptResume)
    }

    static func unbind() {
        lock.lock()
        defer { lock.unlock() }
        resume?.unswizzle()
        resume = nil
    }

    /// Swizzles `URLSessionTask.resume()` method.
    class Resume: MethodSwizzler<@convention(c) (URLSessionTask, Selector) -> Void, @convention(block) (URLSessionTask) -> Void> {
        private static let selector = #selector(URLSessionTask.resume)

        private let method: Method

        static func build() throws -> Resume {
            return try Resume(selector: self.selector, klass: URLSessionTask.self)
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
}
