/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FlagsClient {
    public static let defaultName = "default"

    private let configuration: FlagsClient.Configuration
    private let httpClient: FlagsHTTPClient
    private let repository: any FlagsRepositoryProtocol
    private let exposureLogger: any ExposureLogging
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    internal init(
        configuration: FlagsClient.Configuration,
        httpClient: FlagsHTTPClient,
        repository: any FlagsRepositoryProtocol,
        exposureLogger: any ExposureLogging,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.repository = repository
        self.exposureLogger = exposureLogger
        self.dateProvider = dateProvider
        self.featureScope = featureScope
    }

    @discardableResult
    public static func create(
        name: String = FlagsClient.defaultName,
        with configuration: FlagsClient.Configuration = .init(),
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            return try runOnMainThreadSync {
                try createOrThrow(name: name, with: configuration, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
            return NOPFlagsClient()
        }
    }

    public static func instance(
        named name: String = FlagsClient.defaultName,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClientProtocol {
        do {
            guard let clientRegistry = core.get(feature: FlagsFeature.self)?.clientRegistry else {
                throw ProgrammerError(
                    description: "Flags feature must be enabled before calling `FlagsClient.instance(named:in:)`."
                )
            }
            guard let client = clientRegistry.client(named: name) else {
                throw ProgrammerError(
                    description: "Flags client '\(name)' not found. Make sure that you call `FlagsClient.create(name:with:in:)` first."
                )
            }
            return client
        } catch let error {
            consolePrint("\(error)", .error)
            return NOPFlagsClient()
        }
    }

    internal static func createOrThrow(
        name: String,
        with configuration: FlagsClient.Configuration,
        in core: DatadogCoreProtocol
    ) throws -> FlagsClientProtocol {
        guard let clientRegistry = core.get(feature: FlagsFeature.self)?.clientRegistry else {
            throw ProgrammerError(
                description: "Flags feature must be enabled before calling `FlagsClient.create(name:with:in:)`."
            )
        }
        guard !clientRegistry.isRegistered(clientName: name) else {
            throw ProgrammerError(
                description: "A flags client named '\(name)' already exists."
            )
        }

        let featureScope = core.scope(for: FlagsFeature.self)
        let client = FlagsClient(
            configuration: configuration,
            httpClient: NetworkFlagsHTTPClient(),
            repository: FlagsRepository(clientName: name, featureScope: featureScope),
            exposureLogger: ExposureLogger(featureScope: featureScope),
            dateProvider: SystemDateProvider(),
            featureScope: featureScope
        )

        clientRegistry.register(client, named: name)
        return client
    }
}

extension FlagsClient: FlagsClientProtocol {
    public func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {
        featureScope.context { [httpClient, configuration] sdkContext in
            httpClient.postPrecomputeAssignments(
                context: context,
                configuration: configuration,
                sdkContext: sdkContext
            ) { [weak self] result in
                guard let self else {
                    completion(.failure(.clientNotInitialized))
                    return
                }

                switch result {
                case .success(let (data, response)):
                    guard
                        let httpResponse = response as? HTTPURLResponse,
                        200...299 ~= httpResponse.statusCode
                    else {
                        completion(.failure(.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: data)
                        self.repository.setFlagAssignments(response.flags, for: context, date: dateProvider.now)
                        completion(.success(()))
                    } catch {
                        completion(.failure(.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
        }
    }

    public func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        guard let flagAssignment = repository.flagAssignment(for: key) else {
            return FlagDetails(key: key, value: defaultValue, error: .flagNotFound)
        }

        guard let value = flagAssignment.variation(as: T.self) else {
            return FlagDetails(key: key, value: defaultValue, error: .typeMismatch)
        }

        let details = FlagDetails(
            key: key,
            value: value,
            variant: flagAssignment.variationKey,
            reason: flagAssignment.reason
        )

        if let context = repository.context {
            exposureLogger.logExposure(
                at: dateProvider.now,
                for: key,
                assignment: flagAssignment,
                context: context
            )
        }

        return details
    }
}
