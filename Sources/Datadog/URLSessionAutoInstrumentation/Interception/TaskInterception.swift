/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class TaskInterception {
    internal let request: URLRequest
    private(set) var metrics: TaskMetrics?
    private(set) var completion: TaskCompletion?

    init(request: URLRequest) {
        self.request = request
    }

    func register(metrics: URLSessionTaskMetrics) {
        self.metrics = TaskMetrics(metrics: metrics)
    }

    func register(response: URLResponse?, error: Error?) {
        self.completion = TaskCompletion(response: response, error: error)
    }

    var isDone: Bool {
        metrics != nil && completion != nil
    }
}

internal struct TaskCompletion {
    let httpResponse: HTTPURLResponse?
    let error: Error?

    init(response: URLResponse?, error: Error?) {
        self.httpResponse = response as? HTTPURLResponse
        self.error = error
    }
}

internal struct TaskMetrics {
    let taskStartTime: Date
    let taskEndTime: Date

    // TODO: RUMM-718 Compute more metrics

    init(metrics: URLSessionTaskMetrics) {
        self.taskStartTime = metrics.taskInterval.start
        self.taskEndTime = metrics.taskInterval.end
    }
}
