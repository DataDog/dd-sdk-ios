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

    private static func logDataStoreDiagnostic(_ message: String, startedAt: Date, details: String? = nil) {
        let now = Date()
        let elapsedMs = now.timeIntervalSince(startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        let details = details.map { " \($0)" } ?? ""
        print(
            "Datadog Flags data store \(message)\(details) at \(now.timeIntervalSince1970) elapsedMs=\(elapsedMs) thread=\(thread)"
        )
    }

    func setFlagsData(_ flagsData: FlagsData, forClientNamed clientName: String) {
        let startedAt = Date()
        Self.logDataStoreDiagnostic("setFlagsData start", startedAt: startedAt, details: "clientName=\(clientName)")
        guard let data = encodeFlagsData(flagsData, diagnosticStartedAt: startedAt) else {
            return
        }

        setEncodedFlagsData(data, forClientNamed: clientName, diagnosticStartedAt: startedAt)
    }

    func encodeFlagsData(_ flagsData: FlagsData, diagnosticStartedAt: Date? = nil) -> Data? {
        if let diagnosticStartedAt {
            Self.logDataStoreDiagnostic("encode start", startedAt: diagnosticStartedAt)
        }

        do {
            let data = try Self.encoder.encode(flagsData)
            if let diagnosticStartedAt {
                Self.logDataStoreDiagnostic("encode end", startedAt: diagnosticStartedAt, details: "bytes=\(data.count)")
            }
            return data
        } catch let error {
            if let diagnosticStartedAt {
                Self.logDataStoreDiagnostic("encode failed", startedAt: diagnosticStartedAt, details: "error=\(error)")
            }
            DD.logger.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            featureScope.telemetry.error("Failed to encode \(type(of: flagsData)) in Flags Data Store", error: error)
            return nil
        }
    }

    func setEncodedFlagsData(_ data: Data, forClientNamed clientName: String, diagnosticStartedAt: Date? = nil) {
        if let diagnosticStartedAt {
            Self.logDataStoreDiagnostic("dataStore setValue start", startedAt: diagnosticStartedAt)
        }
        featureScope.dataStore.setValue(data, forKey: clientName)
        if let diagnosticStartedAt {
            Self.logDataStoreDiagnostic("dataStore setValue returned", startedAt: diagnosticStartedAt)
        }
    }

    func flagsData(forClientNamed clientName: String, callback: @escaping (FlagsData?) -> Void) {
        let startedAt = Date()
        Self.logDataStoreDiagnostic("flagsData read start", startedAt: startedAt, details: "clientName=\(clientName)")
        featureScope.dataStore.value(forKey: clientName) { result in
            let hasData = result.data() != nil
            Self.logDataStoreDiagnostic("flagsData read callback received", startedAt: startedAt, details: "hasData=\(hasData)")
            guard let data = result.data() else {
                Self.logDataStoreDiagnostic("flagsData read callback returning nil", startedAt: startedAt)
                callback(nil)
                return
            }

            do {
                Self.logDataStoreDiagnostic("decode start", startedAt: startedAt, details: "bytes=\(data.count)")
                let flagsData = try Self.decoder.decode(FlagsData.self, from: data)
                Self.logDataStoreDiagnostic("decode end", startedAt: startedAt)
                callback(flagsData)
            } catch let error {
                Self.logDataStoreDiagnostic("decode failed", startedAt: startedAt, details: "error=\(error)")
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
