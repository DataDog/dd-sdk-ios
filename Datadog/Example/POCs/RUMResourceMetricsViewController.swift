/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

internal class DDURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private struct TaskMetrics: CustomStringConvertible {
        let duration: (start: Date, end: Date)
        let dns: (start: Date, end: Date)?

        init(metrics: URLSessionTaskMetrics) {
            self.duration = (
                start: metrics.taskInterval.start,
                end: metrics.taskInterval.end
            )
            self.dns = metrics.transactionMetrics.first.flatMap { firstTransaction in
                (
                    start: firstTransaction.domainLookupStartDate ?? Date(),
                    end: firstTransaction.domainLookupEndDate ?? Date()
                )
            }
        }

        var description: String {
            var string = "[duration: \(duration.end.timeIntervalSince(duration.start))]"
            if let dns = dns {
                string += ", [dns: \(dns.end.timeIntervalSince(dns.start))]"
            }
            return string
        }
    }

    private var metricsByTaskIdentifier: [Int: TaskMetrics] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        metricsByTaskIdentifier[task.taskIdentifier] = TaskMetrics(metrics: metrics)

        print("""
            🧪 Received metrics: \(task.originalRequest!.url)
            - metrics: \(metricsByTaskIdentifier[task.taskIdentifier]!)
        """)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let metrics = metricsByTaskIdentifier[task.taskIdentifier]

        print("""
            🧪 Task completed: \(task.originalRequest!.url)
            - data.count: \(task.countOfBytesReceived)
            - has response: \(task.response != nil)
            - has error: \(error != nil)
            - metrics: \(metrics!)
        """)

        let traceID = task.originalRequest?.allHTTPHeaderFields?["x-datadog-trace-id"]
        let spanID = task.originalRequest?.allHTTPHeaderFields?["x-datadog-parent-id"]

        // Here:
        // - produce APM Span
        // - stop RUM Resource with timing information

        _ = traceID
        _ = spanID
    }
}

internal class RUMResourceMetricsViewController: UIViewController {
    private let delegate = DDURLSessionDelegate()
    private var session: URLSession!

    override func viewDidLoad() {
        super.viewDidLoad()

        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let url = URL(string: "https://picsum.photos/200/300")!

        var request = URLRequest(url: url)
        request = injectTracingHeaders(to: request)

//        let task = session.dataTask(with: request)
        let task = session.dataTask(with: request) { (data, response, error) in
            print("""
                🧪 Completion block:
                - data.count: \(data?.count ?? -1)
                - has response: \(response != nil)
                - has error: \(error != nil)
            """)
        }
        task.resume()

        // Here:
        // - start RUM Resource
    }

    private func injectTracingHeaders(to request: URLRequest) -> URLRequest {
        var mutableRequest = request
        // Following span is never finished. It is only used to inject `traceID` and `spanID`.
        // Those values are later read in `DDURLSessionDelegate` where the actual span is created and send.
        let span = Global.sharedTracer
            .startSpan(operationName: "")

        let httpHeadersWriter = HTTPHeadersWriter()
        httpHeadersWriter.inject(spanContext: span.context)
        httpHeadersWriter.tracePropagationHTTPHeaders.forEach { header in
            mutableRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }
        return mutableRequest
    }
}
