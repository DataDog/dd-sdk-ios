/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import class Datadog.URLSessionInterceptor
import Alamofire

/// An `Alamofire.EventMonitor` which instruments `Alamofire.Session` with Datadog RUM and Tracing.
public class DDEventMonitor: EventMonitor {
    public init() {}

    public func request(_ request: Request, didCreateTask task: URLSessionTask) {
        URLSessionInterceptor.shared?.taskCreated(task: task)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        URLSessionInterceptor.shared?.taskMetricsCollected(task: task, metrics: metrics)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        URLSessionInterceptor.shared?.taskCompleted(task: task, error: error)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        URLSessionInterceptor.shared?.taskReceivedData(task: dataTask, data: data)
    }
}

/// An `Alamofire.RequestInterceptor` which instruments `Alamofire.Session` with Datadog RUM and Tracing.
public class DDRequestInterceptor: RequestInterceptor {
    public init() {}

    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        let instrumentedRequest = URLSessionInterceptor.shared?.modify(request: urlRequest)
        completion(.success(instrumentedRequest ?? urlRequest))
    }
}
