/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsDataStore {
    private static let decoder = JSONDecoder()
    // Older native SDKs and React Native bridges accept only version 1.
    private static let encodedAssignmentsVersion: DataStoreKeyVersion = 2

    let featureScope: FeatureScope
    private let encode: (FlagsData) throws -> Data

    struct EncodedFlagsData {
        let data: Data
        let version: DataStoreKeyVersion
    }

    init(featureScope: FeatureScope, encode: @escaping (FlagsData) throws -> Data = { try JSONEncoder().encode($0) }) {
        self.featureScope = featureScope
        self.encode = encode
    }

    func setFlagsData(_ flagsData: FlagsData, forClientNamed clientName: String) {
        if let encoded = encodeFlagsData(flagsData) {
            setEncodedFlagsData(encoded, forClientNamed: clientName)
        }
    }

    func setEncodedFlagsData(_ encoded: EncodedFlagsData, forClientNamed clientName: String) {
        featureScope.dataStore.setValue(encoded.data, forKey: clientName, version: encoded.version)
    }

    func encodeFlagsData(_ flagsData: FlagsData) -> EncodedFlagsData? {
        do {
            let data = try encode(flagsData)
            let version = flagsData.obfuscation == nil ? dataStoreDefaultKeyVersion : Self.encodedAssignmentsVersion
            return EncodedFlagsData(data: data, version: version)
        } catch let error {
            DD.logger.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            return nil
        }
    }

    func flagsData(forClientNamed clientName: String, callback: @escaping (FlagsData?) -> Void) {
        featureScope.dataStore.value(forKey: clientName) { result in
            let encodedData = result.data(expectedVersion: Self.encodedAssignmentsVersion)
            guard let data = encodedData ?? result.data() else {
                callback(nil)
                return
            }

            do {
                let flagsData = try Self.decoder.decode(FlagsData.self, from: data)
                guard (flagsData.obfuscation != nil) == (encodedData != nil) else {
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
}

internal extension FeatureScope {
    var flagsDataStore: FlagsDataStore {
        FlagsDataStore(featureScope: self)
    }
}
