/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for processing `URLSession` task interceptions.
public protocol DatadogURLSessionInterceptor {
    /// Tells the interceptor to modify a URL request.
    ///
    /// - Parameters:
    ///   - session: The session [processing the request.
    ///   - request: The request to intercept.
    /// - Returns: The modified request.
    func urlSession(_ session: URLSession, intercept request: URLRequest) -> URLRequest

    /// Tells the interceptor that the session did create a task.
    ///
    /// - Parameters:
    ///   - session: The session creating the task.
    ///   - task: The created task.
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)

    /// Tells the interceptor that the session finished collecting metrics for the task.
    ///
    /// - Parameters:
    ///   - session: The session collecting the metrics.
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)

    /// Tells the interceptor that the data task has received some of the expected data.
    /// - Parameters:
    ///   - session: The session containing the data task that provided data.
    ///   - dataTask: The data task that provided data.
    ///   - data: A data object containing the transferred data.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)

    /// Tells the interceptor that the task finished transferring data.
    ///
    /// - Parameters:
    ///   - session: The session containing the task that has finished transferring data.
    ///   - task: The task that has finished transferring data.
    ///   - error: If an error occurred, an error object indicating how the transfer failed, otherwise NULL.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
}

internal struct NOPDatadogURLSessionInterceptor: DatadogURLSessionInterceptor {
    /// no-op
    func urlSession(_ session: URLSession, intercept request: URLRequest) -> URLRequest { request }
    /// no-op
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { }
    /// no-op
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { }
    /// no-op
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { }
    /// no-op
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { }
}
