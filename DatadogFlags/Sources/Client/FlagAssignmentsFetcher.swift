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
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    )
}

internal final class FlagAssignmentsFetcher: FlagAssignmentsFetching {
    let customEndpoint: URL?
    let customHeaders: [String: String]?
    let flagSelection: CanonicalFlagSelection?

    private let featureScope: any FeatureScope
    private let assignmentFetchQueue: DispatchQueue
    private let fetch: (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void

    private static let decoder = JSONDecoder()
    private static let flagSelectionIgnoredHeader = "DD-Flag-Selection-Ignored"

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
        featureScope: any FeatureScope
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil

        let urlSession = URLSession(configuration: configuration)

        self.init(
            customEndpoint: customEndpoint,
            customHeaders: customHeaders,
            flagSelection: flagSelection,
            featureScope: featureScope,
            fetch: urlSession.fetch
        )
    }

    init(
        customEndpoint: URL?,
        customHeaders: [String: String]?,
        flagSelection: CanonicalFlagSelection?,
        featureScope: any FeatureScope,
        assignmentFetchQueue: DispatchQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-flags-assignment-fetch",
            qos: .utility,
            autoreleaseFrequency: .workItem
        ),
        fetch: @escaping (URLRequest, @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.flagSelection = flagSelection
        self.featureScope = featureScope
        self.assignmentFetchQueue = assignmentFetchQueue
        self.fetch = fetch
    }

    func flagAssignments(
        for evaluationContext: FlagsEvaluationContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        // Repository callbacks can invoke application code; keep them off shared SDK work queues.
        let completion: (Result<FlagAssignmentsResponse, FlagsError>) -> Void = { result in
            DispatchQueue.global(qos: .utility).async {
                completion(result)
            }
        }
        featureScope.context { [weak self] context in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            self.assignmentFetchQueue.async {
                self.fetchAssignments(
                    for: evaluationContext,
                    context: context,
                    completion: completion
                )
            }
        }
    }

    private func fetchAssignments(
        for evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        do {
            let request = try URLRequest.flagAssignmentsRequest(
                url: url(with: context),
                evaluationContext: evaluationContext,
                context: context,
                customHeaders: customHeaders,
                flagSelection: flagSelection
            )
            fetch(request) { [assignmentFetchQueue, featureScope, flagSelection] result in
                assignmentFetchQueue.async {
                    Self.handleFetchResult(
                        result,
                        supportsObfuscation: FlagKeyObfuscation.isSupported(source: context.source),
                        requestCarriedFlagSelection: flagSelection != nil,
                        featureScope: featureScope,
                        completion: completion
                    )
                }
            }
        } catch let error {
            DD.logger.error("Failed to encode flag assignments request body.", error: error)
            featureScope.telemetry.error("Failed to encode flag assignments request body.", error: error)
            completion(.failure(.invalidConfiguration))
        }
    }

    private static func handleFetchResult(
        _ result: Result<(Data, HTTPURLResponse), Error>,
        supportsObfuscation: Bool,
        requestCarriedFlagSelection: Bool,
        featureScope: any FeatureScope,
        completion: @escaping (Result<FlagAssignmentsResponse, FlagsError>) -> Void
    ) {
        switch result {
        case let .success((data, httpResponse)):
            if requestCarriedFlagSelection,
               let reason = httpResponse.value(forHTTPHeaderField: flagSelectionIgnoredHeader) {
                DD.logger.error("`Flags.Configuration.flagSelection` was ignored by the server (\(reason)). Loaded the full flag configuration.")
                featureScope.telemetry.debug("Flag selection ignored", attributes: ["reason": reason])
            }
            do {
                let response = try decoder.decode(FlagAssignmentsResponse.self, from: data)
                guard response.obfuscation == nil || supportsObfuscation else {
                    throw FlagsError.invalidResponse
                }

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

                completion(.success(response))
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
        completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void
    ) {
        let task = self.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            completion(.success((data, httpResponse)))
        }
        task.resume()
    }
}
