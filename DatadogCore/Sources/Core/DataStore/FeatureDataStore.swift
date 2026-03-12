/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A concrete implementation of the `DataStore` protocol using file storage.
///
/// Actor isolation replaces the `DispatchQueue` previously used for serialising
/// file I/O. The `DataStore` protocol methods remain synchronous (fire-and-forget)
/// by bridging through `Task`, matching the original queue-based semantics.
internal actor FeatureDataStore: DataStore {
    enum Constants {
        /// The version of this data store implementation.
        /// If a breaking change is introduced to the format of managed files, the version must be upgraded and old data should be deleted.
        static let dataStoreVersion = 1
    }

    /// The name of the feature this instance of data store operates on.
    private let feature: String
    /// The directory specific to the instance of SDK that holds this feature.
    private let coreDirectory: CoreDirectory
    /// The data store directory path specific to the `feature`.
    /// It is relative path inside `coreDirectory`.
    nonisolated let directoryPath: String
    /// The telemetry endpoint for sending data store errors.
    private let telemetry: Telemetry

    init(
        feature: String,
        directory: CoreDirectory,
        telemetry: Telemetry
    ) {
        self.feature = feature
        self.coreDirectory = directory
        self.directoryPath = directory.getDataStorePath(forFeatureNamed: feature)
        self.telemetry = telemetry
    }

    // MARK: - DataStore (nonisolated bridging to actor)

    nonisolated func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        Task { await _setValue(value, forKey: key, version: version) }
    }

    nonisolated func value(forKey key: String, callback: @escaping @Sendable (DataStoreValueResult) -> Void) {
        Task { await _value(forKey: key, callback: callback) }
    }

    nonisolated func removeValue(forKey key: String) {
        Task { await _removeValue(forKey: key) }
    }

    nonisolated func clearAllData() {
        Task { await _clearAllData() }
    }

    // MARK: - Actor-isolated implementations

    private func _setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        do {
            try write(data: value, forKey: key, version: version)
        } catch let error {
            DD.logger.error("[Data Store] Error on setting `\(key)` value for `\(feature)`", error: error)
            telemetry.error("[Data Store] Error on setting `\(key)` value for `\(feature)`", error: DDError(error: error))
        }
    }

    private func _value(forKey key: String, callback: @escaping @Sendable (DataStoreValueResult) -> Void) {
        do {
            let result = try readData(forKey: key)
            callback(result)
        } catch let error {
            callback(.error(error))
            DD.logger.error("[Data Store] Error on getting `\(key)` value for `\(feature)`", error: error)
            telemetry.error("[Data Store] Error on getting `\(key)` value for `\(feature)`", error: DDError(error: error))
        }
    }

    private func _removeValue(forKey key: String) {
        do {
            try deleteData(forKey: key)
        } catch let error {
            DD.logger.error("[Data Store] Error on deleting `\(key)` value for `\(feature)`", error: error)
            telemetry.error("[Data Store] Error on deleting `\(key)` value for `\(feature)`", error: DDError(error: error))
        }
    }

    private func _clearAllData() {
        do {
            let directory = try coreDirectory.coreDirectory.subdirectoryIfExists(path: directoryPath)
            try directory?.deleteAllFiles()
        } catch let error {
            DD.logger.error("[Data Store] Error on clearing all data for `\(feature)`", error: error)
            telemetry.error("[Data Store] Error on clearing all data for `\(feature)`", error: DDError(error: error))
        }
    }

    // MARK: - Persistence

    private func write(data: Data, forKey key: String, version: DataStoreKeyVersion) throws {
        let directory = try coreDirectory.coreDirectory.createSubdirectory(path: directoryPath)

        let file: File
        if directory.hasFile(named: key) {
            file = try directory.file(named: key)
        } else {
            file = try directory.createFile(named: key)
        }

        let writer = DataStoreFileWriter(file: file)
        try writer.write(data: data, version: version)
    }

    private func readData(forKey key: String) throws -> DataStoreValueResult {
        guard let directory = try? coreDirectory.coreDirectory.subdirectory(path: directoryPath) else {
            return .noValue
        }

        guard directory.hasFile(named: key) else {
            return .noValue
        }

        let file = try directory.file(named: key)
        let reader = DataStoreFileReader(file: file)
        let (data, version) = try reader.read()
        return .value(data, version)
    }

    private func deleteData(forKey key: String) throws {
        guard let directory = try? coreDirectory.coreDirectory.subdirectory(path: directoryPath) else {
            return
        }

        if directory.hasFile(named: key) {
            try directory.file(named: key).delete()
        }
    }
}

extension FeatureDataStore: Flushable {
    /// Blocks the caller thread until all pending actor work completes.
    nonisolated func flush() {
        let sem = DispatchSemaphore(value: 0)
        Task { await _drain(); sem.signal() }
        sem.wait()
    }

    private func _drain() {
        // Actor processes this after any pending tasks, effectively draining the mailbox.
    }
}
