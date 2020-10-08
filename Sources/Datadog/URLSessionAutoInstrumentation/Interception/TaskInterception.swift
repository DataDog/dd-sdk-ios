/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class TaskInterception {
    /// An identifier uniquely identifying the task interception across all `URLSessions`.
    internal let identifier: UUID
    /// The initial request send during this interception. It is, the request send from `URLSession`, not the one
    /// given by the user (as the request could have been modified in `URLSessionSwizzler`).
    internal let request: URLRequest
    /// Task metrics collected during this interception.
    private(set) var metrics: ResourceMetrics?
    /// Task completion collected during this interception.
    private(set) var completion: ResourceCompletion?

    init(request: URLRequest) {
        self.identifier = UUID()
        self.request = request
    }

    func register(metrics: ResourceMetrics) {
        self.metrics = metrics
    }

    func register(completion: ResourceCompletion) {
        self.completion = completion
    }

    /// Tells if the interception is done (mean: both metrics and completion were collected).
    var isDone: Bool {
        metrics != nil && completion != nil
    }
}

internal struct ResourceCompletion {
    let httpResponse: HTTPURLResponse?
    let error: Error?

    init(response: URLResponse?, error: Error?) {
        self.httpResponse = response as? HTTPURLResponse
        self.error = error
    }
}

/// Encapsulates key metrics retrieved from `URLSessionTaskMetrics`.
/// Reference: https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics
internal struct ResourceMetrics {
    /// Properties of the fetch phase for the resource:
    /// - `start` -  the time when the task started fetching the resource from the server,
    /// - `end` - the time immediately after the task received the last byte of the resource.
    let fetch: (start: Date, end: Date)

    /// Properties of the name lookup phase for the resource.
    let dns: (start: Date, duration: TimeInterval)?

    /// The size of data delivered to delegate or completion handler.
    let responseSize: Int64?
}

extension ResourceMetrics {
    init(taskMetrics: URLSessionTaskMetrics) {
        // Set default values
        var fetch = (start: taskMetrics.taskInterval.start, end: taskMetrics.taskInterval.end)
        var dns: (start: Date, duration: TimeInterval)? = nil
        var responseSize: Int64? = nil

        // Capture more precise values
        if let lastTransactionMetrics = taskMetrics.transactionMetrics.last {
            // TODO: RUMM-719 When computing other timings, check if it's correct to only depend on the last `transactionMetrics`

            if let fetchStart = lastTransactionMetrics.fetchStartDate,
               let fetchEnd = lastTransactionMetrics.responseEndDate {
                fetch = (start: fetchStart, end: fetchEnd)
            }

            if let dnsStart = lastTransactionMetrics.domainLookupStartDate,
               let dnsEnd = lastTransactionMetrics.domainLookupEndDate {
                dns = (start: dnsStart, duration: dnsEnd.timeIntervalSince(dnsStart))
            }

            if #available(iOS 13.0, *) {
                responseSize = lastTransactionMetrics.countOfResponseBodyBytesAfterDecoding
            }
        }

        self.init(fetch: fetch, dns: dns, responseSize: responseSize)
    }
}
