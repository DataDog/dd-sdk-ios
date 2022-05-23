/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal final class DatadogCoreMock: DatadogCoreProtocol, Flushable {
    private var v1Features: [String: Any] = [:]

    /// Flush resgistered features.
    ///
    /// The method will also call `flush` on any `Flushable` registered
    /// feature.
    func flush() {
        all(Flushable.self).forEach { $0.flush() }
        v1Features = [:]
    }

    /// Gets all registered feature of a given type.
    ///
    /// - Parameter type: The desired feature type.
    /// - Returns: Array of feature.
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

/// `Flushable` object resets its state on flush.
///
/// Calling `flush` method should reset any in-memory and persistent
/// data to initialised state.
internal protocol Flushable {
    /// Flush data and reset state.
    func flush()
}

extension LoggingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension TracingFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMFeature: Flushable {
    func flush() {
        deinitialize()
    }
}

extension RUMInstrumentation: Flushable {
    func flush() {
        deinitialize()
    }
}
