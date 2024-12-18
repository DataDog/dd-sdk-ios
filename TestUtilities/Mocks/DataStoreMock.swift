/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class DataStoreMock: DataStore {
    @ReadWriteLock
    public var storage: [String: DataStoreValueResult]

    init(storage: [String: DataStoreValueResult] = [:]) {
        self.storage = storage
    }

    public func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        storage[key] = .value(value, version)
    }

    public func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        callback(storage[key] ?? .noValue)
    }

    public func removeValue(forKey key: String) {
        storage[key] = nil
    }

    public func clearAllData() {
        storage.removeAll()
    }

    // MARK: - Side Effects Observation

    public func value(forKey key: String) -> DataStoreValueResult? {
        return storage[key]
    }
}
