/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal extension FeatureScope {
    /// Data store endpoint suited for RUM data.
    var rumDataStore: RUMDataStore {
        RUMDataStore(featureScope: self)
    }

    /// RUM data store endpoint within SDK context.
    func rumDataStoreContext(_ block: @escaping (DatadogContext, RUMDataStore) -> Void) {
        dataStoreContext { context, dataStore in
            block(context, rumDataStore)
        }
    }
}

/// RUM interface for data store.
///
/// It stores values in JSON format and implements convenience for type-safe key referencing and data serialization.
/// Serialization errors are logged to telemetry.
internal struct RUMDataStore {
    internal enum Key: String {
        /// References pending App Hang information.
        /// If found during app start it is considered a fatal hang in previous process.
        case fatalAppHangKey = "fatal-app-hang"
        case watchdogAppStateKey = "watchdog-app-state"
        case watchdogRUMViewEvent = "watchdog-rum-view-event"
        case anonymousId = "rum-anonymous-id"
    }

    /// Encodes values in RUM data store.
    private static let encoder = JSONEncoder()
    /// Decodes values in RUM data store.
    private static let decoder = JSONDecoder()

    /// RUM feature scope.
    let featureScope: FeatureScope

    func setValue<V: Codable>(_ value: V, forKey key: Key, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion) {
        do {
            let data = try RUMDataStore.encoder.encode(value)
            featureScope.dataStore.setValue(data, forKey: key.rawValue, version: version)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: value)) in RUM Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: value)) in RUM Data Store", error: error)
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
                let value = try RUMDataStore.decoder.decode(V.self, from: data)
                callback(value)
            } catch let error {
                DD.logger.error("Failed to decode \(V.self) from RUM Data Store", error: error)
                featureScope.telemetry.error("Failed to decode \(V.self) from RUM Data Store", error: error)
                callback(nil)
            }
        }
    }

    func removeValue(forKey key: Key) {
        featureScope.dataStore.removeValue(forKey: key.rawValue)
    }
}
