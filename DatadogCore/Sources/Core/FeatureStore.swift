/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Thread-safe registry for features, their storage, and upload units.
///
/// This replaces the `@ReadWriteLock` synchronization previously used in `DatadogCore`
/// for protecting the `stores` and `features` dictionaries.
///
/// **Why a class with NSLock instead of an actor?**
/// `DatadogFeature` (and related types like `Flushable`, `DataStore`) are not `Sendable`.
/// Swift 6 strict concurrency forbids returning non-Sendable types across actor isolation
/// boundaries (`await actor.method()` → non-Sendable return is a compile-time error).
/// Because features are stored inside the registry and returned to callers, the actor
/// model cannot be used without first making every feature `Sendable` — a cross-cutting
/// change across all modules. `NSLock` provides equivalent runtime safety without
/// requiring Sendable conformance at type boundaries.
internal final class FeatureStore: @unchecked Sendable {
    private let lock = NSLock()

    /// Registry for remote features (storage and upload units).
    private var stores: [String: (storage: FeatureStorage, upload: FeatureUpload)] = [:]

    /// Registry for all features.
    private var features: [String: DatadogFeature] = [:]

    // MARK: - Feature Registration

    func addStore(name: String, storage: FeatureStorage, upload: FeatureUpload) {
        lock.lock()
        defer { lock.unlock() }
        stores[name] = (storage: storage, upload: upload)
    }

    func addFeature(name: String, feature: DatadogFeature) {
        lock.lock()
        defer { lock.unlock() }
        features[name] = feature
    }

    // MARK: - Feature Retrieval

    func feature<T>(named name: String, type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return features[name] as? T
    }

    func storage(for name: String) -> FeatureStorage? {
        lock.lock()
        defer { lock.unlock() }
        return stores[name]?.storage
    }

    // MARK: - Bulk Access

    var allStorages: [FeatureStorage] {
        lock.lock()
        defer { lock.unlock() }
        return stores.values.map { $0.storage }
    }

    var allUploads: [FeatureUpload] {
        lock.lock()
        defer { lock.unlock() }
        return stores.values.map { $0.upload }
    }

    func allDataStores(in core: DatadogCore) -> [DataStore] {
        lock.lock()
        defer { lock.unlock() }
        return features.values.map { feature in
            FeatureDataStore(
                feature: type(of: feature).name,
                directory: core.directory,
                queue: core.readWriteQueue,
                telemetry: core.telemetry
            )
        }
    }

    var flushableFeatures: [Flushable] {
        lock.lock()
        defer { lock.unlock() }
        return features.values.compactMap { $0 as? Flushable }
    }

    // MARK: - Lifecycle

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stores = [:]
        features = [:]
    }
}
