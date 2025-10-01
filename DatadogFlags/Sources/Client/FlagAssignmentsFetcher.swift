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
    private let customEndpoint: URL?
    private let customHeaders: [String: String]
    private let featureScope: any FeatureScope
    private let fetch: (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void

    private static let decoder = JSONDecoder()

    convenience init(
        customEndpoint: URL?,
        customHeaders: [String: String],
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
        customHeaders: [String: String],
        featureScope: any FeatureScope,
        fetch: @escaping (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void
    ) {
        self.customEndpoint = customEndpoint
        self.customHeaders = customHeaders
        self.featureScope = featureScope
        self.fetch = fetch
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
            let request = URLRequest.flagAssignmentsRequest(
                url: self.url(with: context),
                evaluationContext: evaluationContext,
                context: context,
                customHeaders: self.customHeaders
            )
            self.fetch(request) { result in
                switch result {
                case .success(let data):
                    do {
                        let response = try Self.decoder.decode(FlagAssignmentsResponse.self, from: data)
                        completion(.success(response.flags))
                    } catch {
                        completion(.failure(.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
        }
    }

    private func url(with context: DatadogContext) -> URL {
        customEndpoint ?? context.site.flagsEndpoint.appendingPathComponent("precompute-assignments")
    }
}

extension DatadogSite {
    internal var flagsEndpoint: URL {
        switch self {
        // swiftlint:disable force_unwrapping
        case .us1: return URL(string: "https://ff-cdn.datadoghq.com")!
        case .us3: return URL(string: "https://ff-cdn.us3.datadoghq.com")!
        case .us5: return URL(string: "https://ff-cdn.us5.datadoghq.com")!
        case .eu1: return URL(string: "https://ff-cdn.datadoghq.eu")!
        case .ap1: return URL(string: "https://ff-cdn.ap1.datadoghq.com")!
        case .ap2: return URL(string: "https://ff-cdn.ap2.datadoghq.com")!
        case .us1_fed:
            DD.logger.warn(
                """
                Government sites (us1_fed) are not officially supported for feature flags. \
                Falling back to us1 endpoint.
                """
            )
            return URL(string: "https://ff-cdn.datadoghq.com")!
        // swiftlint:enable force_unwrapping
        }
    }
}

extension URLSession {
    fileprivate func fetch(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
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

            completion(.success(data))
        }
        task.resume()
    }
}
