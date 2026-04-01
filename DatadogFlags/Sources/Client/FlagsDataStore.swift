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

    /// Timeout for data store reads. This is a fallback in case the underlying
    /// DataStore implementation doesn't call the callback (e.g., NOPDataStore).
    private static let readTimeout: TimeInterval = 0.1

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
        // Use a safe wrapper with timeout fallback to guarantee the callback is always
        // invoked, even if the underlying DataStore doesn't call it (e.g., NOPDataStore).
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

    /// Wraps `DataStore.value(forKey:callback:)` with a timeout to guarantee the callback
    /// is always invoked, even if the underlying implementation doesn't call it.
    private func safeDataStoreValue(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        let callbackInvoked = ReadWriteLock(wrappedValue: false)

        // Set up timeout fallback
        let timeoutWorkItem = DispatchWorkItem {
            var shouldInvoke = false
            callbackInvoked.mutate { invoked in
                if !invoked {
                    invoked = true
                    shouldInvoke = true
                }
            }
            if shouldInvoke {
                callback(.noValue)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.readTimeout, execute: timeoutWorkItem)

        // Call the underlying data store
        featureScope.dataStore.value(forKey: key) { result in
            timeoutWorkItem.cancel()
            var shouldInvoke = false
            callbackInvoked.mutate { invoked in
                if !invoked {
                    invoked = true
                    shouldInvoke = true
                }
            }
            if shouldInvoke {
                callback(result)
            }
        }
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
