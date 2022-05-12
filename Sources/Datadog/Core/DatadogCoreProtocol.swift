/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal var DefaultDatadogCore: DatadogCoreProtocol = NOOPDatadogCore()

/// A Datadog Core holds a set of features and is responsible of
/// managing their storage and upload mechanism. It also provides a thread-safe
/// scope for writing events.
public protocol DatadogCoreProtocol {
    /// Registers a feature by its name and configuration.
    ///
    /// - Parameters:
    ///   - named: The feature name.
    ///   - storage: The feature's storage configuration.
    ///   - upload: The feature's upload configuration.
    func registerFeature(named: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration)

    /// Returns a Feature scope by its name.
    ///
    /// - Parameter named: The feature's name.
    /// - Returns: The feature if it was previously registered, `nil` otherwise.
    func scope(forFeature named: String) -> FeatureScope?
}

/// Provide feature specific storage configuration.
public struct FeatureStorageConfiguration {
    // TODO: RUMM-2133
}

/// Provide feature specific upload configuration.
public struct FeatureUploadConfiguration {
    // TODO: RUMM-2133
}

/// A datadog feature providing thread-safe scope for writing events.
public protocol FeatureScope {
    // TODO: RUMM-2133
}

/// No-op implementation of `DatadogFeatureRegistry`.
internal struct NOOPDatadogCore: DatadogCoreProtocol {
    /// no-op
    func registerFeature(named: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration) {}

    /// no-op
    func scope(forFeature named: String) -> FeatureScope? {
        return nil
    }
}
