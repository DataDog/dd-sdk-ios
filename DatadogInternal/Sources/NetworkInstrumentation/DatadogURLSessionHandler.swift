/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for processing `URLSession` task interceptions.
public protocol DatadogURLSessionHandler {
    /// The first party hosts configured for this handler.
    var firstPartyHosts: FirstPartyHosts { get }

    /// Modifies the provided request by injecting trace headers.
    ///
    /// - Parameters:
    ///   - request: The request to be modified.
    ///   - headerTypes: The types of tracing headers to inject into the request.
    /// - Returns: A tuple containing the modified request and the injected TraceContext. If no trace is injected (e.g., due to sampling),
    ///            the returned request remains unmodified, and the trace context will be nil.
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>) -> (URLRequest, TraceContext?)

    /// Notifies the handler that the interception has started.
    ///
    /// - Parameter interception: The URLSession task interception.
    func interceptionDidStart(interception: URLSessionTaskInterception)

    /// Notifies the handler that the interception has completed.
    ///
    /// - Parameter interception: The URLSession task interception.
    func interceptionDidComplete(interception: URLSessionTaskInterception)
}

extension DatadogCoreProtocol {
    /// Core extension for registering `URLSession` handlers.
    ///
    /// - Parameter urlSessionHandler: The `URLSession` handler to register.
    public func register(urlSessionHandler: DatadogURLSessionHandler) throws {
        let feature = get(feature: NetworkInstrumentationFeature.self) ?? .init()
        feature.handlers.append(urlSessionHandler)
        try register(feature: feature)
    }
}
