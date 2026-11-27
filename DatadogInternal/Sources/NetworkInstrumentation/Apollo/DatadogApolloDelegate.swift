/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import Foundation

/// URLSessionDataDelegate for Apollo iOS v2 that enables Datadog network instrumentation.
///
/// This delegate implements URLSessionDataDelegate methods to collect response data and bridge
/// delegate callbacks to async/await continuations. It is designed to be swizzled by Datadog's
/// `URLSessionInstrumentation` to capture network metrics and traces while maintaining thread-safe
/// data collection for Apollo's async networking layer.
///
/// - Note: Must be used with `DatadogApolloURLSession` and registered via
///   `URLSessionInstrumentation.enable(with: .init(delegateClass: DatadogApolloDelegate.self))`
open class DatadogApolloDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var taskData: [URLSessionTask: Data] = [:]
    private var taskContinuations: [URLSessionTask: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private let lock = NSLock()

    /// Registers a continuation for a URLSessionTask to receive data when the request completes.
    ///
    /// This is called internally by `DatadogApolloURLSession` to bridge delegate callbacks
    /// to async/await continuations.
    ///
    /// - Parameters:
    ///   - task: The URLSessionTask to track
    ///   - continuation: The continuation to resume when the task completes
    internal func registerContinuation(for task: URLSessionTask, continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.lock()
        defer { lock.unlock() }
        taskContinuations[task] = continuation
        taskData[task] = Data()
    }

    // MARK: - URLSessionDataDelegate

    /// Called when data is received for a data task.
    ///
    /// This method will be swizzled by Datadog to capture network data for RUM monitoring.
    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        taskData[dataTask]?.append(data)
    }

    /// Called when a task completes with or without error.
    ///
    /// This method will be swizzled by Datadog to capture completion events and metrics.
    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = taskContinuations.removeValue(forKey: task)
        let data = taskData.removeValue(forKey: task) ?? Data()
        lock.unlock()

        if let error = error {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: (data, response))
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }
}
#endif
