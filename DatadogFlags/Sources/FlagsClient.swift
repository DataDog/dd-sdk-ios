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
    private let store: FlagsStore
    private let featureScope: FeatureScope

    internal init(configuration: FlagsClient.Configuration, httpClient: FlagsHTTPClient, store: FlagsStore, featureScope: FeatureScope) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.store = store
        self.featureScope = featureScope
    }

    public static func create(with configuration: FlagsClient.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
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

    internal static func createOrThrow(with configuration: FlagsClient.Configuration, in core: DatadogCoreProtocol) throws -> FlagsClient {
        guard core.get(feature: FlagsFeature.self) != nil else {
            throw ProgrammerError(
                description: "`FlagsClient.create()` produces a non-functional client because the `Flags` feature was not enabled."
            )
        }

        let httpClient = NetworkFlagsHTTPClient()
        let store = FlagsStore()
        let featureScope = core.scope(for: FlagsFeature.self)
        return FlagsClient(configuration: configuration, httpClient: httpClient, store: store, featureScope: featureScope)
    }

    public func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {
        featureScope.context { [httpClient, configuration] sdkContext in
            httpClient.postPrecomputeAssignments(
                context: context,
                configuration: configuration,
                sdkContext: sdkContext
            ) { [weak self] result in
                guard let self = self else {
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
                        self.store.setFlags(response.flags)
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

    @inlinable
    public func getObjectValue<T: Decodable>(key: String, defaultValue: T, using decoder: JSONDecoder = .init()) -> T {
        let anyValue = getValue(key: key, defaultValue: AnyValue.null)
        let value = try? anyValue.as(T.self, using: decoder)
        return value ?? defaultValue
    }

    public func getValue<T: FlagValue>(key: String, defaultValue: T) -> T {
        guard let flagAssignment = store.flagAssignment(for: key) else {
            return defaultValue
        }
        return flagAssignment.variation(as: T.self) ?? defaultValue
    }
}
