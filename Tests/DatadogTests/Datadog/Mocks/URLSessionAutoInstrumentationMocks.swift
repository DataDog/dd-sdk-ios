/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

class URLSessionInterceptorMock: URLSessionInterceptorType {
    var modifiedRequest: URLRequest?

    var onRequestModified: ((URLRequest) -> Void)?
    var onTaskCreated: ((URLSession, URLSessionTask) -> Void)?
    var onTaskCompleted: ((URLSession, URLSessionTask, Error?) -> Void)?
    var onTaskMetricsCollected: ((URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void)?

    var tasksCreated: [(session: URLSession, task: URLSessionTask)] = []
    var tasksCompleted: [(session: URLSession, task: URLSessionTask, error: Error?)] = []
    var taskMetrics: [(session: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics)] = []

    func modify(request: URLRequest) -> URLRequest {
        onRequestModified?(request)
        return modifiedRequest ?? request
    }

    func taskCreated(urlSession: URLSession, task: URLSessionTask) {
        onTaskCreated?(urlSession, task)
        tasksCreated.append((session: urlSession, task: task))
    }

    func taskCompleted(urlSession: URLSession, task: URLSessionTask, error: Error?) {
        onTaskCompleted?(urlSession, task, error)
        tasksCompleted.append((session: urlSession, task: task, error: error))
    }

    func taskMetricsCollected(urlSession: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        onTaskMetricsCollected?(urlSession, task, metrics)
        taskMetrics.append((session: urlSession, task: task, metrics: metrics))
    }
}
