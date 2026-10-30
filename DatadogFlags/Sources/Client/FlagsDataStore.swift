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
    // Older native SDKs and React Native bridges accept only version 1.
    private static let encodedAssignmentsVersion: DataStoreKeyVersion = 2
    // SDKs without flag selection read only versions 1 and 2, so they skip a cache that holds only the selected flags.
    private static let flagSelectionVersion: DataStoreKeyVersion = 3
    private static let knownVersions: Set<DataStoreKeyVersion> = [
        dataStoreDefaultKeyVersion, encodedAssignmentsVersion, flagSelectionVersion
    ]

    let featureScope: FeatureScope

    func setFlagsData(_ flagsData: FlagsData, forClientNamed clientName: String) {
        guard let encoded = encodeFlagsData(flagsData) else {
            return
        }

        setEncodedFlagsData(encoded.data, forClientNamed: clientName, version: encoded.version)
    }

    func encodeFlagsData(_ flagsData: FlagsData) -> (data: Data, version: DataStoreKeyVersion)? {
        do {
            let data = try Self.encoder.encode(flagsData)
            return (data, Self.version(of: flagsData))
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            return nil
        }
    }

    func setEncodedFlagsData(_ data: Data, forClientNamed clientName: String, version: DataStoreKeyVersion) {
        featureScope.dataStore.setValue(data, forKey: clientName, version: version)
    }

    func flagsData(forClientNamed clientName: String, callback: @escaping (FlagsData?) -> Void) {
        featureScope.dataStore.value(forKey: clientName) { result in
            guard case let .value(data, version) = result, Self.knownVersions.contains(version) else {
                callback(nil)
                return
            }

            do {
                let flagsData = try Self.decoder.decode(FlagsData.self, from: data)
                guard Self.version(of: flagsData) == version else {
                    throw FlagsError.invalidResponse
                }
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

    private static func version(of flagsData: FlagsData) -> DataStoreKeyVersion {
        if flagsData.flagSelection != nil {
            return flagSelectionVersion
        }
        return flagsData.obfuscation == nil ? dataStoreDefaultKeyVersion : encodedAssignmentsVersion
    }
}

internal extension FeatureScope {
    var flagsDataStore: FlagsDataStore {
        FlagsDataStore(featureScope: self)
    }
}
