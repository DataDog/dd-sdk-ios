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
    let urlSessionDataDelegateSwizzler: URLSessionDataDelegateSwizzler

    init() {
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
        try urlSessionSwizzler.swizzle(interceptCompletionHandler: interceptCompletionHandler)
    }

    /// Swizzles `URLSessionTask.resume()` method.
    func swizzle(
        interceptResume: @escaping (URLSessionTask) -> Void
    ) throws {
        try urlSessionTaskSwizzler.swizzle(interceptResume: interceptResume)
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
