/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */


import Foundation
import DatadogInternal

public class DataStoreMock: DataStore {
    var values: [String: Data] = [:]
    let version: DataStoreKeyVersion

    public init(version: DataStoreKeyVersion = dataStoreDefaultKeyVersion) {
        self.version = version
    }

    public func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        values[key] = value
    }

    public func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        if let value = values[key] {
            callback(.value(value, version))
        } else {
            callback(.noValue)
        }
    }

    public func removeValue(forKey key: String) {
        values.removeValue(forKey: key)
    }
}
