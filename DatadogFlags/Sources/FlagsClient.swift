/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FlagsClient {
    private let configuration: FlagsClient.Configuration
    private let httpClient: FlagsHttpClient
    private let store: FlagsStore
    private let featureScope: FeatureScope

    internal init(configuration: FlagsClient.Configuration, httpClient: FlagsHttpClient, store: FlagsStore, featureScope: FeatureScope) {
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

        let httpClient = NetworkFlagsHttpClient()
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
                    guard let httpResponse = response as? HTTPURLResponse,
                          200...299 ~= httpResponse.statusCode else {
                        completion(.failure(.invalidResponse))
                        return
                    }

                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

                        if let responseData = json?["data"] as? [String: Any],
                           let attributes = responseData["attributes"] as? [String: Any],
                           let flags = attributes["flags"] as? [String: Any] {
                            self.store.setFlags(flags, context: context)
                            completion(.success(()))
                        } else {
                            completion(.failure(.invalidResponse))
                        }
                    } catch {
                        completion(.failure(.networkError(error)))
                    }

                case .failure(let error):
                    completion(.failure(.networkError(error)))
                }
            }
        }
    }

    public func getBooleanValue(key: String, defaultValue: Bool) -> Bool {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? Bool {
            return value
        }
        return defaultValue
    }

    public func getStringValue(key: String, defaultValue: String) -> String {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? String {
            return value
        }
        return defaultValue
    }

    public func getIntegerValue(key: String, defaultValue: Int64) -> Int64 {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? NSNumber {
            return value.int64Value
        }
        return defaultValue
    }

    public func getDoubleValue(key: String, defaultValue: Double) -> Double {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? NSNumber {
            return value.doubleValue
        }
        return defaultValue
    }

    // TODO: FFL-1047 Replace [String: Any] with OpenFeature.Value-compatible type
    public func getObjectValue(key: String, defaultValue: [String: Any]) -> [String: Any] {
        let flags = store.getFlags()
        if let flagData = flags[key] as? [String: Any],
           let value = flagData["variationValue"] as? [String: Any] {
            return value
        }
        return defaultValue
    }
}
