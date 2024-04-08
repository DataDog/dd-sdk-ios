/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class URLSessionTaskInterception {
    /// An identifier uniquely identifying the task interception across all `URLSessions`.
    public let identifier: UUID
    /// The initial request send during this interception. It is, the request send from `URLSession`, not the one
    /// given by the user (as the request could have been modified in `URLSessionSwizzler`).
    public private(set) var request: ImmutableRequest
    /// Tells if the `request` is send to a 1st party host.
    public let isFirstPartyRequest: Bool
    /// Task metrics collected during this interception.
    public private(set) var metrics: ResourceMetrics?
    /// Task data received during this interception. Can be `nil` if task completed with error.
    public private(set) var data: Data?
    /// Task completion collected during this interception.
    public private(set) var completion: ResourceCompletion?
    /// Trace information propagated with the task. Not available when Tracing is disabled
    /// or when the task was created through `URLSession.dataTask(with:url)` on some iOS13+.
    public private(set) var trace: TraceContext?
    /// The Datadog origin of the Trace.
    ///
    /// Setting the value to 'rum' will indicate that the span is reported as a RUM Resource.
    public private(set) var origin: String?

    init(request: ImmutableRequest, isFirstParty: Bool) {
        self.identifier = UUID()
        self.request = request
        self.isFirstPartyRequest = isFirstParty
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

    /// Tells if the interception is done (mean: both metrics and completion were collected).
    public var isDone: Bool {
        metrics != nil && completion != nil
    }
}

public struct TraceContext {
    public let traceID: TraceID
    public let spanID: SpanID
    public let parentSpanID: SpanID?

    public init(
        traceID: TraceID,
        spanID: SpanID,
        parentSpanID: SpanID? = nil
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
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

public struct ImmutableRequest {
    public let url: URL?
    public let httpMethod: String?
    public let allHTTPHeaderFields: [String: String]?
    public let unsafeOriginal: URLRequest

    public init(request: URLRequest) {
        self.url = request.url
        self.httpMethod = request.httpMethod
        self.allHTTPHeaderFields = request.allHTTPHeaderFields
        self.unsafeOriginal = request
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
        // * if `200 OK` was preceeded by `301` redirection, it will contain 2 transactions.
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
