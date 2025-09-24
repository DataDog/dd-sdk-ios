/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal extension FeatureScope {
    /// Data store endpoint suited for Flags data.
    func flagsDataStore(instanceName: String) -> FlagsDataStore {
        FlagsDataStore(featureScope: self, instanceName: instanceName)
    }

    /// Flags data store endpoint within SDK context.
    func flagsDataStoreContext(instanceName: String, _ block: @escaping (DatadogContext, FlagsDataStore) -> Void) {
        dataStoreContext { context, dataStore in
            block(context, FlagsDataStore(featureScope: self, instanceName: instanceName))
        }
    }
}

/// Low-level layer for Flags storage (similar to RUMDataStore).
///
/// This struct provides the data persistence interface for the Flags feature, handling:
/// - JSON serialization/deserialization of flag data
/// - Type-safe key management for different data types
/// - Error handling and telemetry logging for storage operations
/// - Integration with the Core SDK's DataStore
internal struct FlagsDataStore {
    internal enum Key: String {
        /// References flag data from precompute-assignments API
        case flags = "flags-assignments"
        /// References metadata about the stored flags-assignments, e.g. the evaluation context
        case flagsMetadata = "flags-metadata"
    }

    /// Encodes values in Flags data store.
    private static let encoder = JSONEncoder()
    /// Decodes values in Flags data store.
    private static let decoder = JSONDecoder()

    /// Flags feature scope.
    let featureScope: FeatureScope
    /// Instance name for storage isolation between multiple client instances.
    let instanceName: String

    /// Creates a new FlagsDataStore with the specified feature scope and instance name.
    init(featureScope: FeatureScope, instanceName: String) {
        self.featureScope = featureScope
        self.instanceName = instanceName
    }

    /// Generates an instance-specific storage key for multi-instance isolation.
    private func storageKey(for key: Key) -> String {
        return "\(key.rawValue)-\(instanceName)"
    }

    func setValue<V: Codable>(_ value: V, forKey key: Key, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion) {
        do {
            let data = try FlagsDataStore.encoder.encode(value)
            featureScope.dataStore.setValue(data, forKey: storageKey(for: key), version: version)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: value)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: value)) in Flags Data Store", error: error)
        }
    }

    func value<V: Codable>(forKey key: Key, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion, callback: @escaping (V?) -> Void) {
        featureScope.dataStore.value(forKey: storageKey(for: key)) { result in
            guard let data = result.data(expectedVersion: version) else {
                // One of following:
                // - no value
                // - value but in wrong version → skip
                // - error in reading the value (already logged in telemetry by `store`)
                callback(nil)
                return
            }
            do {
                let value = try FlagsDataStore.decoder.decode(V.self, from: data)
                callback(value)
            } catch let error {
                DD.logger.error("Failed to decode \(V.self) from Flags Data Store", error: error)
                featureScope.telemetry.error("Failed to decode \(V.self) from Flags Data Store", error: error)
                callback(nil)
            }
        }
    }

    func removeValue(forKey key: Key) {
        featureScope.dataStore.removeValue(forKey: storageKey(for: key))
    }
}
