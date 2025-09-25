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

    /// Creates a FlagsClient instance with default configuration.
    ///
    /// - Parameter core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance, or NOPFlagsClient if creation fails.
    public static func create(in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return create(with: Configuration(), name: FlagsClientRegistry.defaultInstanceName, in: core)
    }

    /// Creates a named FlagsClient instance with default configuration.
    ///
    /// - Parameters:
    ///   - name: The unique name for this instance. Required.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance, or NOPFlagsClient if creation fails.
    public static func create(name: String, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return create(with: Configuration(), name: name, in: core)
    }

    /// Creates a FlagsClient instance with custom configuration.
    ///
    /// - Parameters:
    ///   - configuration: Custom configuration for the client.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance, or NOPFlagsClient if creation fails.
    public static func create(with configuration: FlagsClient.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return create(with: configuration, name: FlagsClientRegistry.defaultInstanceName, in: core)
    }

    /// Creates a named FlagsClient instance with custom configuration.
    ///
    /// - Parameters:
    ///   - configuration: Custom configuration for the client.
    ///   - name: The unique name for this instance. Required.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance, or NOPFlagsClient if creation fails.
    public static func create(with configuration: FlagsClient.Configuration, name: String, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            let client = try runOnMainThreadSync {
                try createOrThrow(with: configuration, instanceName: name, in: core)
            }

            // Register the created client in the registry
            FlagsClientRegistry.register(client, named: name)
            return client
        } catch let error {
            DD.logger.error("Failed to create FlagsClient with name '\(name)'", error: error)
            return NOPFlagsClient()
        }
    }

    /// Creates a FlagsClient instance with default configuration, or returns existing if one with the same name exists.
    ///
    /// - Parameter core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance (new or existing).
    public static func createOrGet(in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return createOrGet(with: Configuration(), name: FlagsClientRegistry.defaultInstanceName, in: core)
    }

    /// Creates a named FlagsClient instance with default configuration, or returns existing if one with the same name exists.
    ///
    /// - Parameters:
    ///   - name: The unique name for this instance.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance (new or existing).
    public static func createOrGet(name: String, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return createOrGet(with: Configuration(), name: name, in: core)
    }

    /// Creates a FlagsClient instance with custom configuration, or returns existing if one with the same name exists.
    ///
    /// - Parameters:
    ///   - configuration: Custom configuration for the client.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance (new or existing).
    public static func createOrGet(with configuration: FlagsClient.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        return createOrGet(with: configuration, name: FlagsClientRegistry.defaultInstanceName, in: core)
    }

    /// Creates a named FlagsClient instance with custom configuration, or returns existing if one with the same name exists.
    ///
    /// - Parameters:
    ///   - configuration: Custom configuration for the client.
    ///   - name: The unique name for this instance.
    ///   - core: The DatadogCore instance to use. Defaults to CoreRegistry.default.
    /// - Returns: FlagsClient instance (new or existing).
    public static func createOrGet(with configuration: FlagsClient.Configuration, name: String, in core: DatadogCoreProtocol = CoreRegistry.default) -> FlagsClient {
        // Check if instance already exists
        if FlagsClientRegistry.isRegistered(instanceName: name) {
            return FlagsClientRegistry.instance(named: name)
        }

        // Create new instance if it doesn't exist
        return create(with: configuration, name: name, in: core)
    }

    /// Returns the default FlagsClient instance if it exists.
    ///
    /// - Returns: Default FlagsClient instance if it exists, NOPFlagsClient otherwise.
    public static var `default`: FlagsClient {
        return FlagsClientRegistry.default
    }

    /// Returns the default FlagsClient instance.
    ///
    /// - Returns: Default FlagsClient instance if it exists, NOPFlagsClient otherwise.
    public static func instance() -> FlagsClient {
        return FlagsClientRegistry.default
    }

    /// Returns an existing FlagsClient instance by name.
    ///
    /// - Parameter name: The name of the instance to retrieve.
    /// - Returns: FlagsClient instance if it exists, NOPFlagsClient otherwise.
    public static func instance(named name: String) -> FlagsClient {
        return FlagsClientRegistry.instance(named: name)
    }

    internal static func createOrThrow(with configuration: FlagsClient.Configuration, instanceName: String, in core: DatadogCoreProtocol) throws -> FlagsClient {
        guard core.get(feature: FlagsFeature.self) != nil else {
            throw ProgrammerError(
                description: "`FlagsClient.create()` produces a non-functional client because the `Flags` feature was not enabled."
            )
        }

        let httpClient = NetworkFlagsHTTPClient()
        let featureScope = core.scope(for: FlagsFeature.self)
        let store = FlagsStore(featureScope: featureScope, instanceName: instanceName)
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
