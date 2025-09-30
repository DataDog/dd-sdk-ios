/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FlagsClient {
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

    public static func create(
        with configuration: FlagsClient.Configuration,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> FlagsClient {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            return try runOnMainThreadSync {
                try createOrThrow(with: configuration, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
            fatalError("TODO: FFL-1016 Fallback to NOP Client")
        }
    }

    internal static func createOrThrow(
        with configuration: FlagsClient.Configuration,
        in core: DatadogCoreProtocol
    ) throws -> FlagsClient {
        guard core.get(feature: FlagsFeature.self) != nil else {
            throw ProgrammerError(
                description: "`FlagsClient.create()` produces a non-functional client because the `Flags` feature was not enabled."
            )
        }

        let httpClient = NetworkFlagsHTTPClient()
        let featureScope = core.scope(for: FlagsFeature.self)
        return FlagsClient(
            configuration: configuration,
            httpClient: httpClient,
            // TODO: FFL-1016 Use the provided client name
            repository: FlagsRepository(clientName: "default", featureScope: featureScope),
            exposureLogger: ExposureLogger(featureScope: featureScope),
            dateProvider: SystemDateProvider(),
            featureScope: featureScope
        )
    }

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

// MARK: - Convenience flag evaluation methods

extension FlagsClient {
    @inlinable
    public func getValue<T>(key: String, defaultValue: T) -> T where T: Equatable, T: FlagValue {
        getDetails(key: key, defaultValue: defaultValue).value
    }

    @inlinable
    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getStringValue(key: String, defaultValue: String) -> String {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getIntegerValue(key: String, defaultValue: Int) -> Int {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        getValue(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getObjectValue(key: String, defaultValue: AnyValue) -> AnyValue {
        getValue(key: key, defaultValue: defaultValue)
    }
}

extension FlagsClient {
    @inlinable
    public func getBooleanDetails(key: String, defaultValue: Bool) -> FlagDetails<Bool> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getStringDetails(key: String, defaultValue: String) -> FlagDetails<String> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getIntegerDetails(key: String, defaultValue: Int) -> FlagDetails<Int> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getDoubleDetails(key: String, defaultValue: Double) -> FlagDetails<Double> {
        getDetails(key: key, defaultValue: defaultValue)
    }

    @inlinable
    public func getObjectDetails(key: String, defaultValue: AnyValue) -> FlagDetails<AnyValue> {
        getDetails(key: key, defaultValue: defaultValue)
    }
}
