/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// High-level business logic layer for Flags storage.
///
/// This class manages the application-level concerns for flag storage:
/// - In-memory caching of flags for fast access
/// - Thread-safe operations using concurrent queues
/// - Flag metadata management (timestamps, evaluation contexts)
/// - Business logic for setting/getting flags with proper context
internal class FlagsStore {
    private let featureScope: FeatureScope
    private let clientKey: String?
    private var cachedFlags: [String: Any] = [:]
    private var cachedMetadata: FlagsMetadata?
    private let syncQueue: DispatchQueue

    init(featureScope: FeatureScope, clientKey: String? = nil) {
        self.featureScope = featureScope
        self.clientKey = clientKey
        
        let queueLabel = if let clientKey = clientKey {
            "com.datadoghq.flags.store-\(clientKey)"
        } else {
            "com.datadoghq.flags.store"
        }
        self.syncQueue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        
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

    func getFlagsMetadata() -> FlagsMetadata? {
        return syncQueue.sync { self.cachedMetadata }
    }

    /// Persists in-memory flags and metadata to the underlying data store.
    private func saveToDataStore() {
        let dataStore = featureScope.flagsDataStore(clientKey: clientKey)

        // Save flags
        let codableFlags = CodableFlags(flags: cachedFlags)
        dataStore.setValue(codableFlags, forKey: .flags)
        // Save metadata if available
        if let metadata = cachedMetadata {
            dataStore.setValue(metadata, forKey: .flagsMetadata)
        }
    }

    private func loadFromDataStore() {
        let dataStore = featureScope.flagsDataStore(clientKey: clientKey)
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
