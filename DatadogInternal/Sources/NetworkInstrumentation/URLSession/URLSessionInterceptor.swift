/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `URLSession` Interceptor provides methods for injecting distributed-traces
/// headers into a `URLRequest`and to instrument a `URLURLSessionTask` lifcycle,
/// from its creation to completion.
///
/// Any Feature supporting `URLSession` instrumentation will receive interceptions through
/// their `DatadogURLSessionHandler` implementation.
public struct URLSessionInterceptor {
    let feature: NetworkInstrumentationFeature

    /// Returns the Interceptor registerd in core.
    ///
    /// This method will return an interceptor if any `DatadogURLSessionHandler` have been
    /// registered in the given core.
    public static func shared(in core: DatadogCoreProtocol = CoreRegistry.default) -> URLSessionInterceptor? {
        guard let feature = core.get(feature: NetworkInstrumentationFeature.self) else {
            return nil
        }

        return URLSessionInterceptor(feature: feature)
    }

    /// Tells the interceptor to modify a URL request.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception.
    /// - Returns: The modified request.
    public func intercept(request: URLRequest, additionalFirstPartyHosts: FirstPartyHosts? = nil) -> URLRequest {
        feature.intercept(request: request, additionalFirstPartyHosts: additionalFirstPartyHosts)
    }

    /// Tells the interceptors that a task was created.
    ///
    /// - Parameters:
    ///   - task: The created task.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception.
    public func intercept(task: URLSessionTask, additionalFirstPartyHosts: FirstPartyHosts? = nil) {
        feature.intercept(task: task, additionalFirstPartyHosts: additionalFirstPartyHosts)
    }

    /// Tells the interceptor that metrics were collected for the given task.
    ///
    /// - Parameters:
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    public func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        feature.task(task, didFinishCollecting: metrics)
    }

    /// Tells the interceptor that the task has received some of the expected data.
    ///
    /// - Parameters:
    ///   - task: The data task that provided data.
    ///   - data: A data object containing the transferred data.
    public func task(_ task: URLSessionTask, didReceive data: Data) {
        feature.task(task, didReceive: data)
    }

    /// Tells the interceptor that the task did complete.
    ///
    /// - Parameters:
    ///   - task: The task that has finished transferring data.
    ///   - error: If an error occurred, an error object indicating how the transfer failed, otherwise NULL.
    public func task(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        feature.task(task, didCompleteWithError: error)
    }
}
