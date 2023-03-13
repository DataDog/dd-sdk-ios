/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension TraceID {
    public static func mockAny() -> TraceID {
        return TraceID(rawValue: .mockAny())
    }

    public static func mock(_ rawValue: UInt64) -> TraceID {
        return TraceID(rawValue: rawValue)
    }
}

public class RelativeTracingUUIDGenerator: TraceIDGenerator {
    private(set) var uuid: TraceID
    internal let count: UInt64
    private let queue = DispatchQueue(label: "queue-RelativeTracingUUIDGenerator-\(UUID().uuidString)")

    public init(startingFrom uuid: TraceID, advancingByCount count: UInt64 = 1) {
        self.uuid = uuid
        self.count = count
    }

    public func generate() -> TraceID {
        return queue.sync {
            defer { uuid = uuid + count }
            return uuid
        }
    }
}

private func + (lhs: TraceID, rhs: UInt64) -> TraceID {
    return TraceID(rawValue: (UInt64(String(lhs)) ?? 0) + rhs)
}

extension URLSession {
    public static func mockWith(_ delegate: URLSessionDelegate) -> URLSession {
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
}

public final class URLSessionInterceptorMock: DatadogURLSessionInterceptor {
    public var modifiedRequest: URLRequest?
    public var onRequestInterception: ((URLRequest, URLSession?) -> Void)?
    public var onTaskCreated: ((URLSessionTask, URLSession?) -> Void)?
    public var onTaskReceivedData: ((URLSessionTask, Data) -> Void)?
    public var onTaskCompleted: ((URLSessionTask, Error?) -> Void)?
    public var onTaskMetricsCollected: ((URLSessionTask, URLSessionTaskMetrics) -> Void)?

    public private(set) var tasksCreated: [URLSessionTask] = []
    public private(set) var tasksReceivedData: [(task: URLSessionTask, data: Data)] = []
    public private(set) var tasksCompleted: [(task: URLSessionTask, error: Error?)] = []
    public private(set) var taskMetrics: [(task: URLSessionTask, metrics: URLSessionTaskMetrics)] = []

    public init() { }

    public func interceptedTask(by taskDescription: String) -> URLSessionTask? {
        return tasksCreated.first(where: { $0.taskDescription == taskDescription })
    }

    public func interceptedTaskWithData(by taskDescription: String) -> (task: URLSessionTask, data: Data)? {
        return tasksReceivedData.first(where: { $0.task.taskDescription == taskDescription })
    }

    public func interceptedTaskWithCompletion(by taskDescription: String) -> (task: URLSessionTask, error: Error?)? {
        return tasksCompleted.first(where: { $0.task.taskDescription == taskDescription })
    }

    public func interceptedTaskWithMetrics(by taskDescription: String) -> (task: URLSessionTask, metrics: URLSessionTaskMetrics)? {
        return taskMetrics.first(where: { $0.task.taskDescription == taskDescription })
    }

    // MARK: - DatadogURLSessionInterceptor conformance

    public func urlSession(_ session: URLSession, intercept request: URLRequest) -> URLRequest {
        onRequestInterception?(request, session)
        return modifiedRequest ?? request
    }

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        tasksCreated.append(task)
        onTaskCreated?(task, session)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        taskMetrics.append((task: task, metrics: metrics))
        onTaskMetricsCollected?(task, metrics)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let existingEntryIndex = tasksReceivedData.firstIndex(where: { $0.task === dataTask }) {
            tasksReceivedData[existingEntryIndex].data.append(data)
        } else {
            tasksReceivedData.append((task: dataTask, data: data))
        }
        onTaskReceivedData?(dataTask, data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        tasksCompleted.append((task: task, error: error))
        onTaskCompleted?(task, error)
    }
}
