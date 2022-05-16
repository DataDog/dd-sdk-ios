/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public internal(set) var defaultDatadogCore: DatadogCoreProtocol = NOOPDatadogCore()

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
public protocol DatadogCoreProtocol {
    /// Registers a feature by its name and configuration.
    ///
    /// - Parameters:
    ///   - featureName: The feature name.
    ///   - storage: The feature's storage configuration.
    ///   - upload: The feature's upload configuration.
    func registerFeature(named featureName: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration)

    /// Returns a Feature scope by its name.
    ///
    /// - Parameter featureName: The feature's name.
    /// - Returns: The scope for feature that previously registered, `nil` otherwise.
    func scope(forFeature featureName: String) -> FeatureScope?

    // MARK: V1 interface

    /// Registers a feature instance by its name.
    ///
    /// Passing `nil` will unregister the feature.
    ///
    /// - Parameters:
    ///   - featureName: The feature name.
    ///   - instance: The feature instance.
    func registerFeature(named featureName: String, instance: Any?)

    /// Returns a Feature instance by its name.
    /// 
    /// - Parameters:
    ///   - type: The feature instance type.
    ///   - featureName: The feature's name.
    /// - Returns: The feature if any.
    func feature<T>(_ type: T.Type, named featureName: String) -> T?
}

extension DatadogCoreProtocol {
    /// Returns a Feature instance by its name.
    ///
    /// - Parameter featureName: The feature's name.
    /// - Returns: The feature if any.
    func feature<T>(named featureName: String) -> T? {
        return feature(T.self, named: featureName)
    }
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
    func registerFeature(named featureName: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration) {}

    /// no-op
    func scope(forFeature featureName: String) -> FeatureScope? {
        return nil
    }

    // MARK: V1 interface

    /// no-op
    func registerFeature(named featureName: String, instance: Any?) {}

    /// no-op
    func feature<T>(_ type: T.Type, named featureName: String) -> T? {
        return nil
    }
}
