/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsDataStore {
    private static let encoder = JSONEncoder()
    // Version 2 readers support obfuscated keys but do not understand flag selection or experimentation opt-out.
    private static let encodedAssignmentsVersion: DataStoreKeyVersion = 2
    // Version 3 readers understand flag selection and experimentation opt-out. Earlier readers skip a cache
    // filtered by either, because it does not hold the full flag configuration for its subject.
    private static let filteredAssignmentsVersion: DataStoreKeyVersion = 3
    // Version 4 preserves numeric tokens. Earlier readers must not interpret rounded or placeholder values.
    private static let numericAssignmentsVersion: DataStoreKeyVersion = 4
    private static let knownVersions: Set<DataStoreKeyVersion> = [
        dataStoreDefaultKeyVersion, encodedAssignmentsVersion, filteredAssignmentsVersion, numericAssignmentsVersion
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
            return (data, Self.version(for: flagsData))
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
                let flagsData = try FlagsNumericJSON.decode(FlagsData.self, from: data, cached: true)
                guard Self.version(for: flagsData) == version else {
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

    private static func version(for flagsData: FlagsData) -> DataStoreKeyVersion {
        if flagsData.flags.values.contains(where: { $0.numericConversion != nil }) {
            return numericAssignmentsVersion
        }
        // Protect both key encodings from readers that would ignore the persisted selection or policy.
        if flagsData.flagSelection != nil || flagsData.experimentationOptOutPolicy != nil {
            return filteredAssignmentsVersion
        }
        return flagsData.obfuscation == nil ? dataStoreDefaultKeyVersion : encodedAssignmentsVersion
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
