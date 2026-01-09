/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSessionTask.setState:` private method to detect task completion.
///
/// This swizzler is necessary to capture completion for:
/// - Async/await APIs: These use internal delegates that cannot be swizzled
/// - Delegate-less tasks without completion handlers
///
/// By observing state transitions to `Canceling` (2) or `Completed` (3), we can detect
/// when these tasks finish without relying on delegate callbacks or completion handlers.
///
internal final class URLSessionTaskStateSwizzler {
    private let lock: NSLocking
    private var taskSetState: TaskSetState?

    init(lock: NSLocking = NSLock()) {
        self.lock = lock
    }

    /// Swizzles `URLSessionTask.setState:` method.
    func swizzle(
        interceptSetState: @escaping (URLSessionTask, Int) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        taskSetState = try TaskSetState.build()
        taskSetState?.swizzle(intercept: interceptSetState)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        taskSetState?.unswizzle()
        lock.unlock()
    }

    deinit {
        unswizzle()
    }

    /// Swizzles `URLSessionTask.setState:` method.
    class TaskSetState: MethodSwizzler<@convention(c) (URLSessionTask, Selector, Int) -> Void, @convention(block) (URLSessionTask, Int) -> Void> {
        private static let selector = NSSelectorFromString("setState:")

        private let method: Method

        static func build() throws -> TaskSetState {
            // RUM-2690: We swizzle private `__NSCFLocalSessionTask` class as it appears to be uniformly used
            // in iOS versions 12.x - 17.x. Swizzling the public `URLSessionTask.resume()` doesn't work in 12.x and 13.x.
            // See https://github.com/DataDog/dd-sdk-ios/pull/1637 for full `URLSessionTask` class dumps in major iOS versions.
            let className = "__NSCFLocalSessionTask"
            guard let klass = NSClassFromString(className) else {
                throw InternalError(description: "Failed to swizzle `URLSessionTask.setState:`: `\(className)` class not found.")
            }
            return try TaskSetState(selector: self.selector, klass: klass)
        }

        private init(selector: Selector, klass: AnyClass) throws {
            self.method = try dd_class_getInstanceMethod(klass, selector)
            super.init()
        }

        func swizzle(intercept: @escaping (URLSessionTask, Int) -> Void) {
            typealias Signature = @convention(block) (URLSessionTask, Int) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { task, state in
                    intercept(task, state)
                    previousImplementation(task, Self.selector, state)
                }
            }
        }
    }
}
