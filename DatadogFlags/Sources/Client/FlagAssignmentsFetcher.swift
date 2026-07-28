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

    fileprivate static func logFetchDiagnostic(_ message: String, startedAt: Date) {
        let now = Date()
        let elapsedMs = now.timeIntervalSince(startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        print(
            "Datadog Flags assignment fetch \(message) at \(now.timeIntervalSince1970) elapsedMs=\(elapsedMs) thread=\(thread)"
        )
    }

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let urlSession = URLSession(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            fetch: urlSession.fetch
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
            Self.logFetchDiagnostic("request built", startedAt: startedAt)
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

extension URLSession {
    fileprivate func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let startedAt = Date()
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask creating", startedAt: startedAt)
        let task = self.dataTask(with: request) { data, response, error in
            FlagAssignmentsFetcher.logFetchDiagnostic("URLSession completion received", startedAt: startedAt)

            if let error {
                FlagAssignmentsFetcher.logFetchDiagnostic("URLSession completed with error", startedAt: startedAt)
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
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask resuming", startedAt: startedAt)
        task.resume()
        FlagAssignmentsFetcher.logFetchDiagnostic("URLSession dataTask resumed", startedAt: startedAt)
    }
}
