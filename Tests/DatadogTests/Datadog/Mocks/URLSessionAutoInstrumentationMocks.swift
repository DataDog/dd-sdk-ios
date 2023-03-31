/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
@testable import Datadog

extension URLSession {
    static func mockWith(_ delegate: URLSessionDelegate) -> URLSession {
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
}

class URLSessionInterceptorMock: URLSessionInterceptorType {
    var modifiedRequest: URLRequest?

    var onRequestModified: ((URLRequest, URLSession?) -> Void)?
    var onTaskCreated: ((URLSessionTask, URLSession?) -> Void)?
    var onTaskReceivedData: ((URLSessionTask, Data) -> Void)?
    var onTaskCompleted: ((URLSessionTask, Error?) -> Void)?
    var onTaskMetricsCollected: ((URLSessionTask, URLSessionTaskMetrics) -> Void)?

    private(set) var tasksCreated: [URLSessionTask] = []
    private(set) var tasksReceivedData: [(task: URLSessionTask, data: Data)] = []
    private(set) var tasksCompleted: [(task: URLSessionTask, error: Error?)] = []
    private(set) var taskMetrics: [(task: URLSessionTask, metrics: URLSessionTaskMetrics)] = []

    func interceptedTask(by taskDescription: String) -> URLSessionTask? {
        return tasksCreated.first(where: { $0.taskDescription == taskDescription })
    }

    func interceptedTaskWithData(by taskDescription: String) -> (task: URLSessionTask, data: Data)? {
        return tasksReceivedData.first(where: { $0.task.taskDescription == taskDescription })
    }

    func interceptedTaskWithCompletion(by taskDescription: String) -> (task: URLSessionTask, error: Error?)? {
        return tasksCompleted.first(where: { $0.task.taskDescription == taskDescription })
    }

    func interceptedTaskWithMetrics(by taskDescription: String) -> (task: URLSessionTask, metrics: URLSessionTaskMetrics)? {
        return taskMetrics.first(where: { $0.task.taskDescription == taskDescription })
    }

    // MARK: - URLSessionInterceptorType conformance

    func modify(request: URLRequest, session: URLSession?) -> URLRequest {
        onRequestModified?(request, session)
        return modifiedRequest ?? request
    }

    func taskCreated(task: URLSessionTask, session: URLSession?) {
        tasksCreated.append(task)
        onTaskCreated?(task, session)
    }

    func taskReceivedData(task: URLSessionTask, data: Data) {
        if let existingEntryIndex = tasksReceivedData.firstIndex(where: { $0.task === task }) {
            tasksReceivedData[existingEntryIndex].data.append(data)
        } else {
            tasksReceivedData.append((task: task, data: data))
        }
        onTaskReceivedData?(task, data)
    }

    func taskCompleted(task: URLSessionTask, error: Error?) {
        tasksCompleted.append((task: task, error: error))
        onTaskCompleted?(task, error)
    }

    func taskMetricsCollected(task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        taskMetrics.append((task: task, metrics: metrics))
        onTaskMetricsCollected?(task, metrics)
    }

    let handler: URLSessionInterceptionHandler = URLSessionInterceptionHandlerMock()
}

class URLSessionInterceptionHandlerMock: URLSessionInterceptionHandler {
    var didNotifyInterceptionStart: ((TaskInterception) -> Void)?
    var startedInterceptions: [TaskInterception] = []

    func notify_taskInterceptionStarted(interception: TaskInterception) {
        startedInterceptions.append(interception)
        didNotifyInterceptionStart?(interception)
    }

    var didNotifyInterceptionCompletion: ((TaskInterception) -> Void)?
    var completedInterceptions: [TaskInterception] = []

    func notify_taskInterceptionCompleted(interception: TaskInterception) {
        completedInterceptions.append(interception)
        didNotifyInterceptionCompletion?(interception)
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
