/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension DatadogCoreProtocol {
    // Upcast `DatadogCoreProtocol` instance to `DatadogV1CoreProtocol`
    // to access v1 related implementation.
    // If upcasting fails, a `NOOPDatadogCore` instance is returned.
    var v1: DatadogV1CoreProtocol {
        self as? DatadogV1CoreProtocol ?? NOPDatadogCore()
    }
}

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
public protocol DatadogV1CoreProtocol: DatadogCoreProtocol {
    // MARK: - V1 interface

    /// Registers a feature instance by its type description.
    ///
    /// - Parameter instance: The feaure instance to register
    func register<T>(feature instance: T?)

    /// Returns a Feature instance by its type.
    ///
    /// - Parameters:
    ///   - type: The feature instance type.
    /// - Returns: The feature if any.
    func feature<T>(_ type: T.Type) -> T?

    /// Returns a Feature scope for a given feature type.
    ///
    /// A Feature instance of the given type must be registered, otherwise return `nil`.
    ///
    /// - Parameters:
    ///   - type: The feature instance type.
    /// - Returns: The feature scope if available.
    func scope<T>(for featureType: T.Type) -> FeatureScope?
}

extension NOPDatadogCore: DatadogV1CoreProtocol {
    // MARK: - V1 interface

    /// no-op
    func register<T>(feature instance: T?) {}

    /// no-op
    func feature<T>(_ type: T.Type) -> T? {
        return nil
    }

    /// no-op
    func scope<T>(for featureType: T.Type) -> FeatureScope? {
        return nil
    }
}
