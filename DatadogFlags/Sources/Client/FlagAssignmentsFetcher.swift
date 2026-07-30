/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagAssignmentsFetching {
    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    )
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?

    private let featureScope: any FeatureScope
    private let assignmentFetchQueue: DispatchQueue
    private let fetch: (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void

    private static let decoder = JSONDecoder()

    fileprivate static func logFetchDiagnostic(_ message: String, startedAt: Date, details: String? = nil) {
        let now = Date()
        let elapsedMs = now.timeIntervalSince(startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        let details = details.map { " \($0)" } ?? ""
        print(
            "Datadog Flags assignment fetch \(message)\(details) at \(now.timeIntervalSince1970) elapsedMs=\(elapsedMs) thread=\(thread)"
        )
    }

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let urlSessionFetcher = FlagAssignmentsURLSessionFetcher(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            fetch: urlSessionFetcher.fetch
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        assignmentFetchQueue: DispatchQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-flags-assignment-fetch",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        ),
        fetch: @escaping (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.assignmentFetchQueue = assignmentFetchQueue
        self.fetch = fetch
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        let startedAt = Date()
        Self.logFetchDiagnostic("start", startedAt: startedAt)

        featureScope.context { [weak self] context in
            Self.logFetchDiagnostic("context received", startedAt: startedAt)

            guard let self else {
                Self.logFetchDiagnostic("failed - client deinitialized", startedAt: startedAt)
                completion(.failure(.clientNotInitialized))
                return
            }

            self.assignmentFetchQueue.async {
                self.fetchAssignments(
                    for: evaluationContext,
                    context: context,
                    startedAt: startedAt,
                    completion: completion
                )
            }
        }
    }

    private func fetchAssignments(
        for evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        startedAt: Date,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        do {
            Self.logFetchDiagnostic("building request", startedAt: startedAt)
            let request = try URLRequest.flagAssignmentsRequest(
                url: url(with: context),
                evaluationContext: evaluationContext,
                context: context,
                customHeaders: customHeaders
            )
            let requestDetails = [
                "method=\(request.httpMethod ?? "nil")",
                "host=\(request.url?.host ?? "nil")",
                "path=\(request.url?.path ?? "nil")",
                "timeout=\(request.timeoutInterval)",
                "bodyBytes=\(request.httpBody?.count ?? 0)"
            ].joined(separator: " ")
            Self.logFetchDiagnostic(
                "request built",
                startedAt: startedAt,
                details: requestDetails
            )
            Self.logFetchDiagnostic("starting URLSession fetch", startedAt: startedAt)
            fetch(request) { [assignmentFetchQueue, featureScope] result in
                Self.logFetchDiagnostic("fetch completion received", startedAt: startedAt)

                assignmentFetchQueue.async {
                    Self.handleFetchResult(
                        result,
                        featureScope: featureScope,
                        startedAt: startedAt,
                        completion: completion
                    )
                }
            }
        } catch let error {
            Self.logFetchDiagnostic("failed - invalid request configuration", startedAt: startedAt)
            DD.logger.error("Failed to encode flag assignments request body.", error: error)
            featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
            completion(.failure(.invalidConfiguration))
        }
    }

    private static func handleFetchResult(
        _ result: Result<Data, Error>,
        featureScope: any FeatureScope,
        startedAt: Date,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        switch result {
        case .success(let data):
            do {
                Self.logFetchDiagnostic("decoding response", startedAt: startedAt)
                let response = try decoder.decode(FlagAssignmentsResponse.self, from: data)
                Self.logFetchDiagnostic("response decoded", startedAt: startedAt)

                // Log any flags that failed to decode to telemetry
                if !response.failedFlags.isEmpty {
                    for (flagKey, errorDescription) in response.failedFlags {
                        let error = InternalError(description: errorDescription)
                        DD.logger.warn(
                            "Failed to decode flag '\(flagKey)' from flag assignments response. Flag will be dropped from configuration.",
                            error: error
                        )
                        featureScope.telemetry.debug(
                            "Failed to decode flag '\(flagKey)' from flag assignments response",
                            attributes: [
                                "flagKey": flagKey,
                                "errorDescription": errorDescription
                            ]
                        )
                    }
                }

                Self.logFetchDiagnostic("returning success", startedAt: startedAt)
                completion(.success(response.flags))
            } catch {
                Self.logFetchDiagnostic("failed - invalid response", startedAt: startedAt)
                featureScope.telemetry.error(
                    "Failed to decode \(FlagAssignmentsResponse.self) from flag assignments response",
                    error: error
                )
                completion(.failure(.invalidResponse))
            }
        case .failure(let error):
            Self.logFetchDiagnostic("failed - network error", startedAt: startedAt)
            DD.logger.error("Failed to fetch flag assignments from the server.", error: error)
            featureScope.telemetry.error("Failed to fetch flag assignments from the server", error: error)
            completion(.failure(.networkError(error)))
        }
    }

    private func url(with context: DatadogContext) -> URL {
        customEndpoint ?? context.site.flagsEndpoint().appendingPathComponent("precompute-assignments")
    }
}

private final class FlagAssignmentsURLSessionFetcher {
    private let session: URLSession
    private let metricsDelegate = FlagAssignmentsURLSessionDelegate()

    init(configuration: URLSessionConfiguration) {
        self.session = URLSession(
            configuration: configuration,
            delegate: metricsDelegate,
            delegateQueue: nil
        )
    }

    func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let startedAt = Date()
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask creating", startedAt: startedAt)
        let task = session.dataTask(with: request) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            FlagAssignmentsFetcher.logFetchDiagnostic(
                "URLSession completion received",
                startedAt: startedAt,
                details: "statusCode=\(statusCode.map { String($0) } ?? "nil") dataBytes=\(data?.count ?? 0)"
            )

            if let error {
                FlagAssignmentsFetcher.logFetchDiagnostic(
                    "URLSession completed with error",
                    startedAt: startedAt,
                    details: "error=\(error)"
                )
                completion(.failure(error))
                return
            }

            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                FlagAssignmentsFetcher.logFetchDiagnostic("URLSession completed with bad response", startedAt: startedAt)
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            FlagAssignmentsFetcher.logFetchDiagnostic("URLSession completed with success", startedAt: startedAt)
            completion(.success(data))
        }
        metricsDelegate.register(taskIdentifier: task.taskIdentifier, startedAt: startedAt)
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask resuming", startedAt: startedAt)
        task.resume()
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask resumed", startedAt: startedAt)
    }
}

private final class FlagAssignmentsURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    @ReadWriteLock
    private var startedAtByTaskIdentifier: [Int: Date] = [:]

    func register(taskIdentifier: Int, startedAt: Date) {
        _startedAtByTaskIdentifier.mutate { startedAtByTaskIdentifier in
            startedAtByTaskIdentifier[taskIdentifier] = startedAt
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        var startedAt: Date?
        _startedAtByTaskIdentifier.mutate { startedAtByTaskIdentifier in
            startedAt = startedAtByTaskIdentifier.removeValue(forKey: task.taskIdentifier)
        }

        guard let startedAt else {
            return
        }

        FlagAssignmentsFetcher.logFetchDiagnostic(
            "URLSession metrics collected",
            startedAt: startedAt,
            details: "redirectCount=\(metrics.redirectCount) transactionCount=\(metrics.transactionMetrics.count)"
        )

        for (index, transaction) in metrics.transactionMetrics.enumerated() {
            FlagAssignmentsFetcher.logFetchDiagnostic(
                "URLSession metrics transaction \(index)",
                startedAt: startedAt,
                details: details(for: transaction, startedAt: startedAt)
            )
        }
    }

    private func details(for transaction: URLSessionTaskTransactionMetrics, startedAt: Date) -> String {
        let parts = [
            "fetchType=\(transaction.resourceFetchType)",
            "protocol=\(transaction.networkProtocolName ?? "nil")",
            interval("fetch", from: transaction.fetchStartDate, to: nil, startedAt: startedAt),
            interval("dns", from: transaction.domainLookupStartDate, to: transaction.domainLookupEndDate, startedAt: startedAt),
            interval("connect", from: transaction.connectStartDate, to: transaction.connectEndDate, startedAt: startedAt),
            interval("tls", from: transaction.secureConnectionStartDate, to: transaction.secureConnectionEndDate, startedAt: startedAt),
            interval("request", from: transaction.requestStartDate, to: transaction.requestEndDate, startedAt: startedAt),
            interval("response", from: transaction.responseStartDate, to: transaction.responseEndDate, startedAt: startedAt)
        ].compactMap { $0 }

        return parts.joined(separator: " ")
    }

    private func interval(_ name: String, from startDate: Date?, to endDate: Date?, startedAt: Date) -> String? {
        guard let startDate else {
            return nil
        }

        let startMs = startDate.timeIntervalSince(startedAt) * 1_000
        if let endDate {
            let endMs = endDate.timeIntervalSince(startedAt) * 1_000
            return "\(name)=\(startMs)-\(endMs)ms"
        } else {
            return "\(name)=\(startMs)ms"
        }
    }
}

extension DatadogSite {
    internal func flagsEndpoint(subdomain: String = "preview") -> URL {
        switch self {
        // swiftlint:disable force_unwrapping
        case .us1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        case .us3: return URL(string: "https://\(subdomain).ff-cdn.us3.datadoghq.com")!
        case .us5: return URL(string: "https://\(subdomain).ff-cdn.us5.datadoghq.com")!
        case .eu1: return URL(string: "https://\(subdomain).ff-cdn.datadoghq.eu")!
        case .ap1: return URL(string: "https://\(subdomain).ff-cdn.ap1.datadoghq.com")!
        case .ap2: return URL(string: "https://\(subdomain).ff-cdn.ap2.datadoghq.com")!
        case .uk1: return URL(string: "https://\(subdomain).ff-cdn.uk1.datadoghq.com")!
        case .us1_fed, .us2_fed:
            DD.logger.warn(
                """
                Government sites (us1_fed, us2_fed) are not officially supported for feature flags. \
                Falling back to us1 endpoint.
                """
            )
            return URL(string: "https://\(subdomain).ff-cdn.datadoghq.com")!
        // swiftlint:enable force_unwrapping
        }
    }
}
