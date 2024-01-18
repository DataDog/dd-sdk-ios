/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSession*` methods.
internal final class NetworkInstrumentationSwizzler {
    let telemetry: Telemetry
    let urlSessionSwizzler: URLSessionSwizzler
    let urlSessionTaskSwizzler: URLSessionTaskSwizzler
    let urlSessionTaskDelegateSwizzler: URLSessionTaskDelegateSwizzler
    let urlSessionDataDelegateSwizzler: URLSessionDataDelegateSwizzler

    init(telemetry: Telemetry) {
        self.telemetry = telemetry
        let lock = NSRecursiveLock()
        urlSessionSwizzler = URLSessionSwizzler(lock: lock)
        urlSessionTaskSwizzler = URLSessionTaskSwizzler(lock: lock)
        urlSessionTaskDelegateSwizzler = URLSessionTaskDelegateSwizzler(lock: lock)
        urlSessionDataDelegateSwizzler = URLSessionDataDelegateSwizzler(lock: lock)
    }

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` methods (with `URL` and `URLRequest`).
    func swizzle(
        interceptCompletionHandler: @escaping (URLSessionTask, Data?, Error?) -> Void
    ) throws {
        try urlSessionSwizzler.swizzle(interceptCompletionHandler: { [weak self] task, data, error in
            if !task.wasResumed {
                self?.telemetry.errorOnce(id: "URLSessionTask.resume() swizzling error", error: {
                    let message = "Intercepted completion of task without intercepting its `resume()`"
                    let kind: String? = nil
                    var stack = ""

                    // The task info collected here describes the list of `URLSessionTask` subclasses implemented in
                    // a specific OS version (e.g., iOS 16.2):
                    // ```
                    // - LocalDataTask <...>.<1>
                    //   - super: __NSCFLocalSessionTask
                    //     - super: NSURLSessionTask
                    //       - super: NSObject
                    // ```
                    // This provides the necessary context to adjust `URLSessionTask` swizzling for the reported OS version in telemetry.
                    dump(task, to: &stack)
                    return (message, kind, stack)
                })
            }
            task.wasResumed = false // reset, tasks are recycled

            interceptCompletionHandler(task, data, error)
        })
    }

    /// Swizzles `URLSessionTask.resume()` method.
    func swizzle(
        interceptResume: @escaping (URLSessionTask) -> Void
    ) throws {
        try urlSessionTaskSwizzler.swizzle(interceptResume: { task in
            task.wasResumed = true
            interceptResume(task)
        })
    }

    /// Swizzles  methods:
    /// - `URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:)`
    /// - `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`
    func swizzle(
        delegateClass: URLSessionTaskDelegate.Type,
        interceptDidFinishCollecting: @escaping (URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void,
        interceptDidCompleteWithError: @escaping (URLSession, URLSessionTask, Error?) -> Void
    ) throws {
        try urlSessionTaskDelegateSwizzler.swizzle(
            delegateClass: delegateClass,
            interceptDidFinishCollecting: interceptDidFinishCollecting,
            interceptDidCompleteWithError: interceptDidCompleteWithError
        )
    }

    /// Swizzles  methods:
    /// - `URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)`
    func swizzle(
        delegateClass: URLSessionDataDelegate.Type,
        interceptDidReceive: @escaping (URLSession, URLSessionDataTask, Data) -> Void
    ) throws {
        try urlSessionDataDelegateSwizzler.swizzle(
            delegateClass: delegateClass,
            interceptDidReceive: interceptDidReceive
        )
    }

    /// Unswizzles all.
    func unswizzle() {
        urlSessionSwizzler.unswizzle()
        urlSessionTaskSwizzler.unswizzle()
        urlSessionTaskDelegateSwizzler.unswizzle()
        urlSessionDataDelegateSwizzler.unswizzle()
    }
}

private enum AssociatedKeys {
    static var wasResumed: UInt8 = 2
}

private extension URLSessionTask {
    /// If task's `URLSessionTask.resume()` was intercepted.
    var wasResumed: Bool {
        set { objc_setAssociatedObject(self, &AssociatedKeys.wasResumed, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_COPY) }
        get { (objc_getAssociatedObject(self, &AssociatedKeys.wasResumed) as? Bool) ?? false }
    }
}
