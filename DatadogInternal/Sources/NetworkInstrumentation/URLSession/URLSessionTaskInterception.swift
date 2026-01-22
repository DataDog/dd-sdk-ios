/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines the tracking mode for network instrumentation.
public enum TrackingMode {
    /// Automatic mode: tracks all tasks without requiring delegate registration.
    /// Does not capture detailed timing data.
    case automatic

    /// Metrics mode: tracks tasks with registered delegate.
    /// Captures `URLSessionTaskMetrics` for detailed timing breakdown (DNS, SSL, TTFB, etc.).
    case metrics
}

public class URLSessionTaskInterception {
    /// An identifier uniquely identifying the task interception across all `URLSessions`.
    public let identifier: UUID
    /// The initial request send during this interception. It is, the request send from `URLSession`, not the one
    /// given by the user (as the request could have been modified in `URLSessionSwizzler`).
    public private(set) var request: ImmutableRequest
    /// Tells if the `request` is send to a 1st party host.
    public let isFirstPartyRequest: Bool
    /// The tracking mode for this interception (automatic or metrics).
    internal let trackingMode: TrackingMode
    /// Task metrics collected during this interception.
    public private(set) var metrics: ResourceMetrics?
    /// Task data received during this interception.
    ///
    /// Data is collected in:
    /// - Metrics mode: via `URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)` swizzling
    /// - Automatic mode: via completion handler swizzling (only for tasks with completion handlers)
    ///
    /// Can be `nil` if:
    /// - Task completed with error
    /// - Task has no completion handler in automatic mode (e.g., async/await, tasks without handlers)
    /// - Task is a download task (data is saved to file instead of captured in memory)
    public private(set) var data: Data?
    /// Response size in bytes received during this interception.
    ///
    /// This is captured via `task.countOfBytesReceived` and serves as a fallback when `metrics.responseSize` is unavailable.
    ///
    /// Priority for response size:
    /// 1. `metrics.responseSize` - Most accurate, from `URLSessionTaskMetrics` (only available in metrics mode)
    /// 2. `responseSize` - Fallback from `task.countOfBytesReceived` (available in both modes)
    ///
    /// Available even when data is not captured (e.g., for tasks without completion handlers in automatic mode).
    public private(set) var responseSize: Int64?
    /// Task completion collected during this interception.
    public private(set) var completion: ResourceCompletion?
    /// Trace context injected to request headers. Can be `nil` if the trace was not sampled or if modifying
    /// request was not possible in `URLSession` swizzling on certain OS version.
    public private(set) var trace: TraceContext?
    /// The Datadog origin of the Trace.
    ///
    /// Setting the value to 'rum' will indicate that the span is reported as a RUM Resource.
    public private(set) var origin: String?
    /// Task state tracked via `setState:` swizzling.
    internal var taskState: URLSessionTask.State?

    /// Approximate start time captured in Automatic mode when interception begins.
    public private(set) var startDate: Date?

    /// Approximate end time captured in Automatic mode when interception completes.
    internal var endDate: Date?

    /// Returns the most accurate start time available.
    /// Prefers `URLSessionTaskMetrics` timing (metrics mode) over approximate timing (automatic mode).
    public var fetchStartDate: Date? {
        return metrics?.fetch.start ?? startDate
    }

    /// Returns the most accurate end time available.
    /// Prefers `URLSessionTaskMetrics` timing (metrics mode) over approximate timing (automatic mode).
    public var fetchEndDate: Date? {
        return metrics?.fetch.end ?? endDate
    }

    init(request: ImmutableRequest, isFirstParty: Bool, trackingMode: TrackingMode) {
        self.identifier = UUID()
        self.request = request
        self.isFirstPartyRequest = isFirstParty
        self.trackingMode = trackingMode
    }

    func register(metrics: ResourceMetrics) {
        self.metrics = metrics
    }

    func register(nextData: Data) {
        if data != nil {
            self.data?.append(nextData)
        } else {
            self.data = nextData
        }
    }

    func register(request: ImmutableRequest) {
        self.request = request
    }

    func register(response: URLResponse?, error: Error?) {
        self.completion = ResourceCompletion(
            response: response as? HTTPURLResponse,
            error: error
        )
    }

    public func register(trace: TraceContext) {
        self.trace = trace
    }

    public func register(origin: String) {
        self.origin = origin
    }

    func register(state: Int) {
        self.taskState = URLSessionTask.State(rawValue: state)
    }

    func register(responseSize: Int64) {
        self.responseSize = responseSize
    }

    func register(startDate: Date) {
        self.startDate = startDate
    }

    func register(endDate: Date) {
        self.endDate = endDate
    }

    /// Tells if the interception is done.
    ///
    /// The completion criteria depends on the tracking mode:
    /// - Automatic mode: Task is done when we have completion OR task state indicates completion.
    /// - Metrics mode: Task is done when we have BOTH metrics AND completion.
    ///   We must wait for metrics to ensure detailed timing data is captured.
    public var isDone: Bool {
        switch trackingMode {
        case .automatic:
            // In automatic mode, complete as soon as we have completion or state completion
            let isStateComplete = taskState == .completed
            return completion != nil || isStateComplete
        case .metrics:
            // In metrics mode, wait for both metrics AND completion
            // to ensure we capture detailed timing data
            return completion != nil && metrics != nil
        }
    }
}

public struct ResourceCompletion {
    public let httpResponse: HTTPURLResponse?
    public let error: Error?

    public init(response: URLResponse?, error: Error?) {
        self.httpResponse = response as? HTTPURLResponse
        self.error = error
    }
}

/// Encapsulates key metrics retrieved either from `URLSessionTaskMetrics` or any other relevant data source.
/// Reference: https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics
public struct ResourceMetrics {
    public struct DateInterval {
        public let start, end: Date
        public var duration: TimeInterval { end.timeIntervalSince(start) }

        public static func create(start: Date?, end: Date?) -> DateInterval? {
            if let start = start, let end = end {
                return DateInterval(start: start, end: end)
            }
            return nil
        }

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// Properties of the fetch phase for the resource:
    /// - `start` -  the time when the task started fetching the resource from the server,
    /// - `end` - the time immediately after the task received the last byte of the resource.
    public let fetch: DateInterval

    /// Properties of the redirection phase for the resource. If the resource is retrieved in multiple transactions,
    /// only the last one is used to track detailed metrics (`dns`, `connect` etc.).
    /// All but last are described as a single "redirection" phase.
    public let redirection: DateInterval?

    /// Properties of the name lookup phase for the resource.
    public let dns: DateInterval?

    /// Properties of the connect phase for the resource.
    public let connect: DateInterval?

    /// Properties of the secure connect phase for the resource.
    public let ssl: DateInterval?

    /// Properties of the TTFB phase for the resource.
    public let firstByte: DateInterval?

    /// Properties of the download phase for the resource.
    public let download: DateInterval?

    /// The size of data delivered to delegate or completion handler.
    public let responseSize: Int64?

    public init(
        fetch: DateInterval,
        redirection: DateInterval?,
        dns: DateInterval?,
        connect: DateInterval?,
        ssl: DateInterval?,
        firstByte: DateInterval?,
        download: DateInterval?,
        responseSize: Int64?
    ) {
        self.fetch = fetch
        self.redirection = redirection
        self.dns = dns
        self.connect = connect
        self.ssl = ssl
        self.firstByte = firstByte
        self.download = download
        self.responseSize = responseSize
    }
}

extension ResourceMetrics {
    public init(taskMetrics: URLSessionTaskMetrics) {
        let fetch = DateInterval(
            start: taskMetrics.taskInterval.start,
            end: taskMetrics.taskInterval.end
        )

        let transactions = taskMetrics.transactionMetrics
            .filter { $0.resourceFetchType != .localCache } // ignore loads from cache

        // Note: `transactions` contain metrics for each individual
        // `request → response` transaction done for given resource, e.g.:
        // * if `200 OK` was received, it will contain 1 transaction,
        // * if `200 OK` was preceded by `301` redirection, it will contain 2 transactions.
        let mainTransaction = transactions.last
        let redirectionTransactions = transactions.dropLast()

        var redirection: DateInterval? = nil

        if redirectionTransactions.count > 0 {
            let redirectionStarts = redirectionTransactions.compactMap { $0.fetchStartDate }
            let redirectionEnds = redirectionTransactions.compactMap { $0.responseEndDate }

            // If several redirections were made, we model them as a single "redirection"
            // phase starting in the first moment of the youngest and ending
            // in the last moment of the oldest.
            if let redirectionPhaseStart = redirectionStarts.first,
               let redirectionPhaseEnd = redirectionEnds.last {
                redirection = DateInterval(start: redirectionPhaseStart, end: redirectionPhaseEnd)
            }
        }

        var dns: DateInterval? = nil
        var connect: DateInterval? = nil
        var ssl: DateInterval? = nil
        var firstByte: DateInterval? = nil
        var download: DateInterval? = nil
        var responseSize: Int64? = nil

        if let mainTransaction = mainTransaction {
            if let dnsStart = mainTransaction.domainLookupStartDate,
               let dnsEnd = mainTransaction.domainLookupEndDate {
                dns = DateInterval(start: dnsStart, end: dnsEnd)
            }

            if let connectStart = mainTransaction.connectStartDate,
               let connectEnd = mainTransaction.connectEndDate {
                connect = DateInterval(start: connectStart, end: connectEnd)
            }

            if let sslStart = mainTransaction.secureConnectionStartDate,
               let sslEnd = mainTransaction.secureConnectionEndDate {
                ssl = DateInterval(start: sslStart, end: sslEnd)
            }

            if let firstByteStart = mainTransaction.requestStartDate, // Time from start requesting the resource ...
               let firstByteEnd = mainTransaction.responseStartDate { // ... to receiving the first byte of the response
                firstByte = DateInterval(start: firstByteStart, end: firstByteEnd)
            }

            if let downloadStart = mainTransaction.responseStartDate, // Time from the first byte of the response ...
               let downloadEnd = mainTransaction.responseEndDate {    // ... to receiving the last byte.
                download = DateInterval(start: downloadStart, end: downloadEnd)
            }

            if #available(iOS 13.0, tvOS 13, *) {
                responseSize = mainTransaction.countOfResponseBodyBytesAfterDecoding
            }
        }

        self.init(
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
