/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Represents the version of data format stored for a key in the data store.
///
/// As values are persisted, the format of data may change between different SDK versions. To prevent decoding errors,
/// callers can utilize `DataStoreKeyVersion` to explicitly specify the version of serialized `Data` before attempting deserialization.
public typealias DataStoreKeyVersion = UInt16

/// The default version of data stored for keys (equals `0`).
public let dataStoreDefaultKeyVersion: DataStoreKeyVersion = 0

/// Possible results of retrieving a value from the data store.
public enum DataStoreValueResult {
    /// The value was found and serialized using the format defined by the specified version.
    case value(Data, DataStoreKeyVersion)
    /// There was no value associated with the requested key.
    case noValue
    /// The value could not be read due to an underlying error.
    /// This may represent an error with the file format or an I/O exception that occurred during reading.
    case error(Error)

    /// Retrieves the data value associated with the result, if it matches the expected version.
    ///
    /// - Parameter expectedVersion: The version expected for the retrieved data.
    /// - Returns: The data value if the version matches the expected version; otherwise, nil.
    public func data(expectedVersion: DataStoreKeyVersion = dataStoreDefaultKeyVersion) -> Data? {
        guard case .value(let data, let storedVersion) = self, storedVersion == expectedVersion else {
            return nil
        }
        return data
    }
}

/// Defines the interface for a data store capable of storing key-value pairs for a given feature.
public protocol DataStore {
    /// Sets the value for the specified key in the data store.
    ///
    /// - Parameters:
    ///   - value: The data to be stored.
    ///   - key: The unique identifier for the data. Must be a valid file name, as it will be persisted in files.
    ///   - version: The version of the data format. Defaults to `0`.
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion)

    /// Retrieves the value associated with the specified key from the data store.
    ///
    /// - Parameters:
    ///   - key: The unique identifier for the data. Must be a valid file name, as it will be persisted in files.
    ///   - callback: A closure providing the result asynchronously on an internal queue.
    ///
    /// Note: The implementation must log errors to console and notify them through telemetry. Callers are not required
    /// to implement logging of errors upon receiving `.error()` result.
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void)

    /// Deletes the value associated with the specified key from the data store.
    ///
    /// - Parameter key: The unique identifier for the value to be deleted. Must be a valid file name, as it will be persisted in files.
    func removeValue(forKey key: String)

    /// Clears all data that has not already yet been uploaded Datadog servers.
    ///
    /// Note: This may impact the SDK's ability to detect App Hangs and Watchdog Terminations
    /// or other features that rely on data persisted in the data store.
    func clearAllData()
}

public extension DataStore {
    /// Sets the value for the specified key in the data store with the default `version` of `0`.
    ///
    /// - Parameters:
    ///   - value: The data to be stored.
    ///   - key: The unique identifier for the data. Must be a valid file name, as it will be persisted in files.
    func setValue(_ value: Data, forKey key: String) {
        setValue(value, forKey: key, version: dataStoreDefaultKeyVersion)
    }
}

public struct NOPDataStore: DataStore {
    public init() {}

    /// no-op
    public func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
    /// no-op
    public func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {}
    /// no-op
    public func removeValue(forKey key: String) {}
    /// no-op
    public func clearAllData() {}
}
