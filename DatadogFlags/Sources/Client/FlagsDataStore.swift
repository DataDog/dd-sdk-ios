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
        guard let data = encodeFlagsData(flagsData) else {
            return
        }

        setEncodedFlagsData(data, forClientNamed: clientName)
    }

    func encodeFlagsData(_ flagsData: FlagsData) -> Data? {
        do {
            return try Self.encoder.encode(flagsData)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            return nil
        }
    }

    func setEncodedFlagsData(_ data: Data, forClientNamed clientName: String) {
        featureScope.dataStore.setValue(data, forKey: clientName)
    }

    func flagsData(forClientNamed clientName: String, callback: @escaping (FlagsData?) -> Void) {
        featureScope.dataStore.value(forKey: clientName) { result in
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

    func removeFlagsData(forClientNamed clientName: String) {
        featureScope.dataStore.removeValue(forKey: clientName)
    }
}

internal extension FeatureScope {
    var flagsDataStore: FlagsDataStore {
        FlagsDataStore(featureScope: self)
    }
}
