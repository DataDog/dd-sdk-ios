/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Alamofire

/// An `Alamofire.EventMonitor` which instruments `Alamofire.Session` with Datadog RUM and Tracing.
public class DDEventMonitor: EventMonitor {
    /// The instance of the SDK core notified by this monitor.
    private weak var core: DatadogCoreProtocol?

    private var interceptor: URLSessionInterceptor? {
        let core = self.core ?? CoreRegistry.default
        return URLSessionInterceptor.shared(in: core)
    }

    public required init(core: DatadogCoreProtocol? = nil ) {
        self.core = core
    }

    public func request(_ request: Request, didCreateTask task: URLSessionTask) {
        interceptor?.intercept(task: task)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptor?.task(task, didFinishCollecting: metrics)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        interceptor?.task(task, didCompleteWithError: error)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        interceptor?.task(dataTask, didReceive: data)
    }
}

/// An `Alamofire.RequestInterceptor` which instruments `Alamofire.Session` with Datadog RUM and Tracing.
public class DDRequestInterceptor: RequestInterceptor {
/// The instance of the SDK core notified by this monitor.
    private weak var core: DatadogCoreProtocol?

    private var interceptor: URLSessionInterceptor? {
        let core = self.core ?? CoreRegistry.default
        return URLSessionInterceptor.shared(in: core)
    }

    public required init(core: DatadogCoreProtocol? = nil ) {
        self.core = core
    }

    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        let instrumentedRequest = interceptor?.intercept(request: urlRequest) ?? urlRequest
        completion(.success(instrumentedRequest))
    }
}
