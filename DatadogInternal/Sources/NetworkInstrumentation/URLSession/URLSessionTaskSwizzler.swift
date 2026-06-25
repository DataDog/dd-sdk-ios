/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class URLSessionTaskSwizzler {
    private let lock: NSLocking
    private var taskResume: TaskResume?
    private var nwTaskResume: NWTaskResume?

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
        // NWURLSessionTask bypasses __NSCFLocalSessionTask, so it needs a separate swizzle.
        nwTaskResume = NWTaskResume.build()
        nwTaskResume?.swizzle(intercept: interceptResume)
    }

    /// Unswizzles all.
    ///
    /// This method is called during deinit.
    func unswizzle() {
        lock.lock()
        taskResume?.unswizzle()
        nwTaskResume?.unswizzle()
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
            // See https://github.com/DataDog/dd-sdk-ios/pull/1637 for full `URLSessionTask` class dumps in major iOS versions.
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

    /// Swizzles `NWURLSessionTask.resume()`.
    class NWTaskResume: MethodSwizzler<@convention(c) (URLSessionTask, Selector) -> Void, @convention(block) (URLSessionTask) -> Void> {
        private static let selector = #selector(URLSessionTask.resume)

        private let method: Method

        /// Returns `nil` if `NWURLSessionTask` is unavailable or if no completion hook is present.
        /// Both conditions are required: tracking resume without completion would leave interceptions open permanently.
        /// Accepts either `completeTaskWithError:` or `completeTaskWithError:retryable:` (iOS 26+).
        static func build() -> NWTaskResume? {
            guard let klass = NSClassFromString("NWURLSessionTask"),
                  class_getInstanceMethod(klass, NSSelectorFromString("completeTaskWithError:")) != nil ||
                  class_getInstanceMethod(klass, NSSelectorFromString("completeTaskWithError:retryable:")) != nil else {
                return nil
            }
            return try? NWTaskResume(selector: self.selector, klass: klass)
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
