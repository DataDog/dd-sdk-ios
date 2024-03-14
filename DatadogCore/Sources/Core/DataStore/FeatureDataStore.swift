/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A concrete implementation of the `DataStore` protocol using file storage.
internal final class FeatureDataStore: DataStore {
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
    internal let directoryPath: String
    /// The queue for managing data store operations.
    private let queue: DispatchQueue
    /// The telemetry endpoint for sending data store errors.
    private let telemetry: Telemetry

    init(
        feature: String,
        directory: CoreDirectory,
        queue: DispatchQueue,
        telemetry: Telemetry
    ) {
        self.feature = feature
        self.coreDirectory = directory
        self.directoryPath = "\(Constants.dataStoreVersion)/" + feature
        self.queue = queue
        self.telemetry = telemetry
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            do {
                try self.write(data: value, forKey: key, version: version)
            } catch let error {
                DD.logger.error("[Data Store] Error on setting `\(key)` value for `\(self.feature)`", error: error)
                self.telemetry.error("[Data Store] Error on setting `\(key)` value for `\(self.feature)`", error: DDError(error: error))
            }
        }
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            do {
                let result = try self.readData(forKey: key)
                callback(result)
            } catch let error {
                callback(.error(error))
                DD.logger.error("[Data Store] Error on getting `\(key)` value for `\(self.feature)`", error: error)
                self.telemetry.error("[Data Store] Error on getting `\(key)` value for `\(self.feature)`", error: DDError(error: error))
            }
        }
    }

    func removeValue(forKey key: String) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            do {
                try self.deleteData(forKey: key)
            } catch let error {
                DD.logger.error("[Data Store] Error on deleting `\(key)` value for `\(self.feature)`", error: error)
                self.telemetry.error("[Data Store] Error on deleting `\(key)` value for `\(self.feature)`", error: DDError(error: error))
            }
        }
    }

    // MARK: - Persistence

    private func write(data: Data, forKey key: String, version: DataStoreKeyVersion) throws {
        // Get or create storage directory. We call it each time, to take into account that
        // the parent `cache/` location might be erased by the OS at any moment.
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
        // Get storage directory if it exists.
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
        // Get storage directory if it exists.
        guard let directory = try? coreDirectory.coreDirectory.subdirectory(path: directoryPath) else {
            return
        }

        if directory.hasFile(named: key) {
            try directory.file(named: key).delete()
        }
    }
}

extension FeatureDataStore: Flushable {
    func flush() {
        queue.sync {}
    }
}
