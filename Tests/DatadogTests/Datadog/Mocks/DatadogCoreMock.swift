/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

internal final class DatadogCoreMock: DatadogCoreProtocol {
    private var v1Features: [String: Any] = [:]

    func flush() {
        v1Features = [:]
    }

    func all<T>(_ type: T.Type) -> [T] {
        v1Features.values.compactMap { $0 as? T }
    }

    /// no-op
    func registerFeature(named featureName: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration) {}

    /// no-op
    func scope(forFeature featureName: String) -> FeatureScope? {
        return nil
    }

    // MARK: V1 interface

    func registerFeature(named featureName: String, instance: Any?) {
        v1Features[featureName] = instance
    }

    func feature<T>(_ type: T.Type, named featureName: String) -> T? {
        return v1Features[featureName] as? T
    }
}
