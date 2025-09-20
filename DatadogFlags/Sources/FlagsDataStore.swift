/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal extension FeatureScope {
    /// Data store endpoint suited for Flags data.
    var flagsDataStore: FlagsDataStore {
        FlagsDataStore(featureScope: self)
    }

    /// Flags data store endpoint within SDK context.
    func flagsDataStoreContext(_ block: @escaping (DatadogContext, FlagsDataStore) -> Void) {
        dataStoreContext { context, dataStore in
            block(context, FlagsDataStore(featureScope: self))
        }
    }
}

/// Flags interface for data store.
///
/// It stores values in JSON format and implements convenience for type-safe key referencing and data serialization.
/// Serialization errors are logged to telemetry.
internal struct FlagsDataStore {
    internal enum Key: String {
        /// References cached flags data from precompute-assignments API
        case flags = "flags-cache"
        /// References metadata about the flags including fetch timestamp and context
        case flagsMetadata = "flags-metadata"
    }

    /// Encodes values in Flags data store.
    private static let encoder = JSONEncoder()
    /// Decodes values in Flags data store.
    private static let decoder = JSONDecoder()

    /// Flags feature scope.
    let featureScope: FeatureScope

    func setValue<V: Codable>(_ value: V, forKey key: Key, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion) {
        do {
            let data = try FlagsDataStore.encoder.encode(value)
            featureScope.dataStore.setValue(data, forKey: key.rawValue, version: version)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: value)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: value)) in Flags Data Store", error: error)
        }
    }

    func value<V: Codable>(forKey key: Key, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion, callback: @escaping (V?) -> Void) {
        featureScope.dataStore.value(forKey: key.rawValue) { result in
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
        featureScope.dataStore.removeValue(forKey: key.rawValue)
    }
}
