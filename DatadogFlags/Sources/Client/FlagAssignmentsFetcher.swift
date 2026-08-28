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
    let assignmentRequestTimeout: TimeInterval?
    let assignmentRequestRetryCount: Int?

    private let featureScope: any FeatureScope
    private let fetch: FlagAssignmentsFetch

    private static let decoder = JSONDecoder()

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        assignmentRequestTimeout: TimeInterval,
        assignmentRequestRetryCount: Int
    ) {
        let assignmentRequestFetch = Flags.AssignmentRequestFetch.urlSession()
        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            featureScope: featureScope,
            fetch: { request, completion in
                assignmentRequestFetch(request, completion: completion)
            },
            assignmentRequestTimeout: assignmentRequestTimeout,
            assignmentRequestRetryCount: assignmentRequestRetryCount
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        fetch: @escaping FlagAssignmentsFetch,
        assignmentRequestTimeout: TimeInterval = 0,
        assignmentRequestRetryCount: Int = 0,
        schedule: @escaping FlagAssignmentsSchedule = FlagAssignmentsRequestOperation.schedule,
        jitter: @escaping (TimeInterval) -> TimeInterval = { upperBound in Double.random(in: 0..<upperBound) },
        now: @escaping () -> Date = Date.init
    ) {
        let policyFetch: FlagAssignmentsFetch
        if assignmentRequestTimeout == 0, assignmentRequestRetryCount == 0 {
            policyFetch = fetch
        } else {
            let composedFetch = Flags.AssignmentRequestFetch(fetch)
                .withTimeout(assignmentRequestTimeout, schedule: schedule)
                .withRetry(
                    assignmentRequestRetryCount,
                    schedule: schedule,
                    jitter: jitter,
                    now: now
                )
            policyFetch = { request, completion in
                composedFetch(request, completion: completion)
            }
        }

        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.assignmentRequestTimeout = assignmentRequestTimeout
        self.assignmentRequestRetryCount = assignmentRequestRetryCount
        self.fetch = policyFetch
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        featureScope: any FeatureScope,
        assignmentRequestFetch: Flags.AssignmentRequestFetch
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.assignmentRequestTimeout = nil
        self.assignmentRequestRetryCount = nil
        self.fetch = { request, completion in
            assignmentRequestFetch(request, completion: completion)
        }
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<[String: FlagAssignment], FlagsError>) -> Void
    ) {
        featureScope.context { [weak self] context in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            do {
                let request = try URLRequest.flagAssignmentsRequest(
                    url: self.url(with: context),
                    evaluationContext: evaluationContext,
                    context: context,
                    customHeaders: self.customHeaders
                )
                let operation = FlagAssignmentsRequestOperation(
                    request: request,
                    timeout: 0,
                    retryCount: 0,
                    fetch: self.fetch,
                    schedule: FlagAssignmentsRequestOperation.schedule,
                    jitter: { _ in 0 },
                    now: Date.init
                )
                operation.start { [featureScope] result in
                    switch result {
                    case .success(let response):
                        guard (200..<300).contains(response.httpResponse.statusCode) else {
                            let error = URLError(.badServerResponse)
                            DD.logger.error("Failed to fetch flag assignments from the server.", error: error)
                            featureScope.telemetry.error("Failed to fetch flag assignments from the server", error: error)
                            completion(.failure(.networkError(error)))
                            return
                        }
                        do {
                            let response = try Self.decoder.decode(
                                FlagAssignmentsResponse.self,
                                from: response.data
                            )

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

                            completion(.success(response.flags))
                        } catch {
                            featureScope.telemetry.error(
                                "Failed to decode \(FlagAssignmentsResponse.self) from flag assignments response",
                                error: error
                            )
                            completion(.failure(.invalidResponse))
                        }
                    case .failure(let error):
                        DD.logger.error("Failed to fetch flag assignments from the server.", error: error)
                        featureScope.telemetry.error("Failed to fetch flag assignments from the server", error: error)
                        completion(.failure(.networkError(error)))
                    }
                }
            } catch let error {
                DD.logger.error("Failed to encode flag assignments request body.", error: error)
                featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
                completion(.failure(.invalidConfiguration))
            }
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
