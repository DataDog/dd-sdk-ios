/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for processing `URLSession` task interceptions.
public protocol DatadogURLSessionInterceptor {
    /// The interceptor's first party hosts
    var firstPartyHosts: FirstPartyHosts { get }

    /// Tells the interceptor to modify a URL request.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Additional 1st-party hosts.
    /// - Returns: The modified request.
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>) -> URLRequest

    /// Asks the interceptor if the request should be intercepted.
    ///
    /// This method should return `false` if the request is internal to Datadog,
    /// e.g POST to intake.
    ///
    /// - Parameter request: The request to intercept.
    /// - Returns: `true` to start intercepting the request.
    func isInternal(request: URLRequest) -> Bool

    /// Tells the interceptor that the session did start.
    ///
    /// - Parameter interception: The URLSession interception.
    func interceptionDidStart(interception: URLSessionTaskInterception)

    /// Tells the interceptor that the session did complete.
    ///
    /// - Parameter interception: The URLSession interception.
    func interceptionDidComplete(interception: URLSessionTaskInterception)
}

internal struct NOPDatadogURLSessionInterceptor: DatadogURLSessionInterceptor {
    /// no-op
    var firstPartyHosts: FirstPartyHosts { .init() }
    /// no-op
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>) -> URLRequest { request }
    /// no-op
    func isInternal(request: URLRequest) -> Bool { false }
    /// no-op
    func interceptionDidStart(interception: URLSessionTaskInterception) { }
    /// no-op
    func interceptionDidComplete(interception: URLSessionTaskInterception) { }
}

extension DatadogCoreProtocol {
    /// Core extension for registering `URLSession` interceptor.
    ///
    /// - Parameter urlSessionInterceptor: The `URLSession` interceptor to register.
    public func register(urlSessionInterceptor: DatadogURLSessionInterceptor) throws {
        let feature = try get(feature: NetworkInstrumentationFeature.self) ?? .init()
        feature.interceptors.append(urlSessionInterceptor)
        try register(feature: feature)
    }
}
