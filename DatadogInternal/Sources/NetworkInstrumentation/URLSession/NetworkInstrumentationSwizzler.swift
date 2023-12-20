/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzles `URLSession*` methods.
internal final class NetworkInstrumentationSwizzler {
    let urlSessionSwizzler: URLSessionSwizzler
    let urlSessionTaskSwizzler: URLSessionTaskSwizzler
    let urlSessionTaskDelegateSwizzler: URLSessionTaskDelegateSwizzler

    init() {
        let lock = NSRecursiveLock()
        urlSessionSwizzler = URLSessionSwizzler(lock: lock)
        urlSessionTaskSwizzler = URLSessionTaskSwizzler(lock: lock)
        urlSessionTaskDelegateSwizzler = URLSessionTaskDelegateSwizzler(lock: lock)
    }

    /// Swizzles `URLSession.dataTask(with:completionHandler:)` methods (with `URL` and `URLRequest`).
    func swizzle(
        interceptCompletionHandler: @escaping (URLSessionTask, Data?, Error?) -> Void
    ) throws {
        try urlSessionSwizzler.swizzle(interceptCompletionHandler: interceptCompletionHandler)
    }

    /// Swizzles `URLSessionTask.resume()` method.
    func swizzle(
        interceptResume: @escaping (URLSessionTask) -> Void
    ) throws {
        try urlSessionTaskSwizzler.swizzle(interceptResume: interceptResume)
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
        try urlSessionTaskDelegateSwizzler.swizzle(
            delegateClass: delegateClass,
            interceptDidReceive: interceptDidReceive,
            interceptDidFinishCollecting: interceptDidFinishCollecting,
            interceptDidCompleteWithError: interceptDidCompleteWithError
        )
    }

    /// Unswizzles all.
    func unswizzle() {
        urlSessionSwizzler.unswizzle()
        urlSessionTaskSwizzler.unswizzle()
        urlSessionTaskDelegateSwizzler.unswizzle()
    }
}
