/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A `DataStore` that schedules all operations on its internal queue.
public final class DataStoreAsyncMock: DataStore {
    @ReadWriteLock
    public var storage: [String: DataStoreValueResult]

    private let queue = DispatchQueue(label: "com.datadoghq.datastore-async-mock")

    public init(storage: [String: DataStoreValueResult] = [:]) {
        self.storage = storage
    }

    public func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        queue.async {
            self.storage[key] = .value(value, version)
        }
    }

    public func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        queue.async {
            callback(self.storage[key] ?? .noValue)
        }
    }

    public func removeValue(forKey key: String) {
        queue.async {
            self.storage[key] = nil
        }
    }

    public func clearAllData() {
        queue.async {
            self.storage.removeAll()
        }
    }

    /// Function to wait until all scheduled operations complete.
    public func flush() {
        queue.sync {}
    }
}
