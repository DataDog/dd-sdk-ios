/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

//swiftlint:disable required_reason_api_name
/// A concrete implementation of the `DataStore` protocol using `UserDefaults`.
public final class UserDefaultsDataStore: DataStore {
    public enum Constants {
        /// The suite name of this data store.
        public static let suiteName = "com.datadoghq.ios-sdk"
    }

    /// The UserDefaults suite instance used for persistence.
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = UserDefaults(suiteName: Constants.suiteName) ?? .standard) {
        self.userDefaults = userDefaults
    }
    //swiftlint:enable required_reason_api_name

    public func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        // Encode version (2 bytes) + data
        var encoded = Data()
        encoded.append(withUnsafeBytes(of: version) { Data($0) })
        encoded.append(value)

        userDefaults.set(encoded, forKey: key)
    }

    public func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        guard let encoded = userDefaults.data(forKey: key) else {
            callback(.noValue)
            return
        }

        // Decode version (first 2 bytes) + data
        guard encoded.count >= MemoryLayout<DataStoreKeyVersion>.size else {
            let error = InternalError(description: "Insufficient data bytes for version.")
            callback(.error(error))
            return
        }

        let version: DataStoreKeyVersion = encoded.prefix(MemoryLayout<DataStoreKeyVersion>.size)
            .withUnsafeBytes { $0.load(as: DataStoreKeyVersion.self) }

        let data = encoded.suffix(from: MemoryLayout<DataStoreKeyVersion>.size)

        callback(.value(data, version))
    }

    public func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    public func clearAllData() {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys {
            userDefaults.removeObject(forKey: key)
        }
    }

    public func flush() { }
}
