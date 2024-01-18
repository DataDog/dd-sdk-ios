/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class URLSessionTaskSwizzler {
    private let lock: NSLocking
    private var taskResume: TaskResume?

    init(lock: NSLocking = NSLock()) {
        self.lock = lock
    }

    /// Swizzles `URLSessionTask.resume()` method.
    func swizzle(
        interceptResume: @escaping (URLSessionTask) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        taskResume = try TaskResume.build()
        taskResume?.swizzle(intercept: interceptResume)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        taskResume?.unswizzle()
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
            // RUM-2690: We swizzle private `__NSCFLocalSessionTask` class as it appears to be uniformly used
            // in iOS versions 12.x - 17.x. Swizzling the public `URLSessionTask.resume()` doesn't work in 12.x and 13.x.
            let className = "__NSCFLocalSessionTask"
            guard let klass = NSClassFromString(className) else {
                throw InternalError(description: "Failed to swizzle `URLSessionTask`: `\(className)` class not found.")
            }
            return try TaskResume(selector: self.selector, klass: klass)
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
