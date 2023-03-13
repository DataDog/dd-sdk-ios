/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The Network Instrumentation Feature that can be registered into a core if
/// any interceptor is provided.
///
/// Usage:
///
///     let core: DatadogCoreProtocol
///
///     let interceptor: DatadogURLSessionInterceptor = CustomDatadogTraceInterceptor()
///     core.register(urlSessionInterceptor: interceptor)
///
/// Registering multiple interceptor will aggregate instrumentation.
internal final class NetworkInstrumentationFeature: DatadogFeature {
    /// The Feature name: "trace-propagation".
    static let name = "network-instrumentation"

    /// A no-op message bus receiver.
    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    /// The list of registered propagators.
    var interceptors: [DatadogURLSessionInterceptor] = []

    init() throws {
        try URLSessionSwizzler.bind()
    }

    deinit {
        URLSessionSwizzler.unbind()
    }
}

extension NetworkInstrumentationFeature: DatadogURLSessionInterceptor {
    func urlSession(_ session: URLSession, intercept request: URLRequest) -> URLRequest {
        interceptors.reduce(request) { $1.urlSession(session, intercept: $0) }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        interceptors.forEach { $0.urlSession(session, didCreateTask: task) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptors.forEach { $0.urlSession(session, task: task, didFinishCollecting: metrics) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        interceptors.forEach { $0.urlSession(session, dataTask: dataTask, didReceive: data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        interceptors.forEach { $0.urlSession(session, task: task, didCompleteWithError: error) }
    }
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
