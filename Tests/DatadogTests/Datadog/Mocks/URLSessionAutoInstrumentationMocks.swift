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
        tasksCreated.append((session: urlSession, task: task))
        onTaskCreated?(urlSession, task)
    }

    func taskCompleted(urlSession: URLSession, task: URLSessionTask, error: Error?) {
        tasksCompleted.append((session: urlSession, task: task, error: error))
        onTaskCompleted?(urlSession, task, error)
    }

    func taskMetricsCollected(urlSession: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        taskMetrics.append((session: urlSession, task: task, metrics: metrics))
        onTaskMetricsCollected?(urlSession, task, metrics)
    }
}

extension ResourceCompletion {
    static func mockAny() -> Self {
        return mockWith()
    }

    static func mockWith(
        response: URLResponse? = .mockAny(),
        error: Error? = nil
    ) -> Self {
        return ResourceCompletion(response: response, error: error)
    }
}

extension ResourceMetrics {
    static func mockAny() -> Self {
        return mockWith()
    }

    static func mockWith(
        fetch: DateInterval = .init(start: Date(), end: Date(timeIntervalSinceNow: 1)),
        redirection: DateInterval? = nil,
        dns: DateInterval? = nil,
        connect: DateInterval? = nil,
        ssl: DateInterval? = nil,
        firstByte: DateInterval? = nil,
        download: DateInterval? = nil,
        responseSize: Int64? = nil
    ) -> Self {
        return .init(
            fetch: fetch,
            redirection: redirection,
            dns: dns,
            connect: connect,
            ssl: ssl,
            firstByte: firstByte,
            download: download,
            responseSize: responseSize
        )
    }
}
