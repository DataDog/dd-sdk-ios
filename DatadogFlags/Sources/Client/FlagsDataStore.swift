/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsDataStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    let featureScope: FeatureScope

    func setFlagsData(_ flagsData: FlagsData, forClientNamed clientName: String) {
        do {
            let data = try Self.encoder.encode(flagsData)
            featureScope.dataStore.setValue(data, forKey: clientName)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
        }
    }

    func flagsData(forClientNamed clientName: String, callback: @escaping (FlagsData?) -> Void) {
        // Use a safe wrapper to guarantee the callback is always invoked,
        // even if the underlying DataStore doesn't call it (e.g., NOPDataStore).
        safeDataStoreValue(forKey: clientName) { result in
            guard let data = result.data() else {
                callback(nil)
                return
            }

            do {
                let flagsData = try Self.decoder.decode(FlagsData.self, from: data)
                callback(flagsData)
            } catch let error {
                DD.logger.error("Failed to decode \(FlagsData.self) from Flags Data Store", error: error)
                featureScope.telemetry.error("Failed to decode \(FlagsData.self) from Flags Data Store", error: error)
                callback(nil)
            }
        }
    }

    /// Wraps `DataStore.value(forKey:callback:)` to guarantee the callback
    /// is always invoked, even if the underlying implementation doesn't call it.
    ///
    /// `NOPDataStore` never invokes callbacks, so we short-circuit for that case.
    private func safeDataStoreValue(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        let dataStore = featureScope.dataStore
        if dataStore is NOPDataStore {
            callback(.noValue)
            return
        }
        dataStore.value(forKey: key, callback: callback)
    }

    func removeFlagsData(forClientNamed clientName: String) {
        featureScope.dataStore.removeValue(forKey: clientName)
    }
}

internal extension FeatureScope {
    var flagsDataStore: FlagsDataStore {
        FlagsDataStore(featureScope: self)
    }
}
