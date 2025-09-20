/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A wrapper around FlagsDataStore that provides the same interface as the original FlagsStore
/// while using the Core SDK's DataStore for persistence.
internal class FlagsStore {
    private let featureScope: FeatureScope
    private var cachedFlags: [String: Any] = [:]
    private var cachedMetadata: FlagsMetadata?
    private let syncQueue = DispatchQueue(label: "com.datadoghq.flags.store", attributes: .concurrent)

    init(featureScope: FeatureScope) {
        self.featureScope = featureScope
        loadFromDataStore()
    }

    func getFlags() -> [String: Any] {
        return syncQueue.sync { self.cachedFlags }
    }

    func setFlags(_ flags: [String: Any]) {
        setFlags(flags, context: nil)
    }

    func setFlags(_ flags: [String: Any], context: FlagsEvaluationContext?) {
        let timestamp = Date().timeIntervalSince1970 * 1_000 // JavaScript-style timestamp in milliseconds

        syncQueue.sync(flags: .barrier) {
            self.cachedFlags = flags
            self.cachedMetadata = FlagsMetadata(
                fetchedAt: timestamp,
                context: context
            )
            self.saveToDataStore()
        }
    }

feat: Replace FlagsStore with DataStore-based implementation

- Remove borrowed ConfigurationStore.swift from Eppo SDK
- Implement FlagsDataStore wrapper following RUM pattern
- Add Codable support to FlagsEvaluationContext and FlagsMetadata
- Create CodableFlags/CodableAny for JSON serialization of Any values
- Update FlagsStore to use featureScope.dataStore for persistence
- Fix tests to use FeatureScopeMock for new constructor

    func getFlagsMetadata() -> FlagsMetadata? {
        return syncQueue.sync { self.cachedMetadata }
    }

    private func saveToDataStore() {
        let dataStore = featureScope.flagsDataStore
        
        // Save flags
        let codableFlags = CodableFlags(flags: cachedFlags)
        dataStore.setValue(codableFlags, forKey: .flags)
        
        // Save metadata if available
        if let metadata = cachedMetadata {
            dataStore.setValue(metadata, forKey: .flagsMetadata)
        }
    }

    private func loadFromDataStore() {
        let dataStore = featureScope.flagsDataStore
        
        // Load flags
        dataStore.value(forKey: .flags) { [weak self] (codableFlags: CodableFlags?) in
            if let codableFlags = codableFlags {
                self?.syncQueue.sync(flags: .barrier) {
                    self?.cachedFlags = codableFlags.toDictionary()
                }
            }
        }
        
        // Load metadata
        dataStore.value(forKey: .flagsMetadata) { [weak self] (metadata: FlagsMetadata?) in
            if let metadata = metadata {
                self?.syncQueue.sync(flags: .barrier) {
                    self?.cachedMetadata = metadata
                }
            }
        }
    }
}
