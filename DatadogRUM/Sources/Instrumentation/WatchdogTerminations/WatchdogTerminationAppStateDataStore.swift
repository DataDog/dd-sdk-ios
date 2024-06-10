/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if canImport(UIKit)
import UIKit
#endif

internal struct CodableDataStore {
    let featureScope: FeatureScope
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    func set(_ value: Codable, forKey key: String, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion) {
        do {
            let data = try Self.encoder.encode(value)
            featureScope.dataStore.setValue(data, forKey: key, version: version)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: value)) in Data Store")
            featureScope.telemetry.error("Failed to encode \(type(of: value)) in Data Store", error: error)
        }
    }

    func value<T: Codable>(forKey key: String, version: DataStoreKeyVersion = dataStoreDefaultKeyVersion, callback: @escaping (T?) -> Void) {
        featureScope.dataStore.value(forKey: key) { result in
            guard let data = result.data(expectedVersion: version) else {
                callback(nil)
                return
            }
            do {
                let value = try Self.decoder.decode(T.self, from: data)
                callback(value)
            } catch let error {
                DD.logger.error("Failed to decode \(T.self) from Data Store")
                featureScope.telemetry.error("Failed to decode \(T.self) from Data Store", error: error)
                callback(nil)
            }
        }
    }

    func removeValue(forKey key: String) {
        featureScope.dataStore.removeValue(forKey: key)
    }
}
