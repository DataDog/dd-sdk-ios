/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for processing `URLSession` task interceptions.
public protocol DatadogURLSessionHandler {
    /// The interceptor's first party hosts
    var firstPartyHosts: FirstPartyHosts { get }

    /// Tells the interceptor to modify a URL request.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Additional 1st-party hosts.
    /// - Returns: The modified request.
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>) -> URLRequest

    /// Tells the interceptor that the session did start.
    ///
    /// - Parameter interception: The URLSession interception.
    func interceptionDidStart(interception: URLSessionTaskInterception)

    /// Tells the interceptor that the session did complete.
    ///
    /// - Parameter interception: The URLSession interception.
    func interceptionDidComplete(interception: URLSessionTaskInterception)
}

internal struct NOPDatadogURLSessionInterceptor: DatadogURLSessionHandler {
    /// no-op
    var firstPartyHosts: FirstPartyHosts { .init() }
    /// no-op
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>) -> URLRequest { request }
    /// no-op
    func interceptionDidStart(interception: URLSessionTaskInterception) { }
    /// no-op
    func interceptionDidComplete(interception: URLSessionTaskInterception) { }
}

extension DatadogCoreProtocol {
    /// Core extension for registering `URLSession` handlers.
    ///
    /// - Parameter urlSessionHandler: The `URLSession` handlers to register.
    public func register(urlSessionHandler: DatadogURLSessionHandler) throws {
        let feature = try get(feature: NetworkInstrumentationFeature.self) ?? .init()
        feature.handlers.append(urlSessionHandler)
        try register(feature: feature)
    }
}
