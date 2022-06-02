/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension DatadogCoreProtocol {
    // Upcast `DatadogCoreProtocol` instance to `DatadogV1CoreProtocol`
    // to access v1 related implementation.
    // If upcasting fails, a `NOOPDatadogCore` instance is returned.
    var v1: DatadogV1CoreProtocol {
        self as? DatadogV1CoreProtocol ?? NOOPDatadogCore()
    }
}

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
internal protocol DatadogV1CoreProtocol: DatadogCoreProtocol {
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

    /// The SDK context created upon core initialization or `nil` if SDK was not yet initialized.
    var context: DatadogV1Context? { get }

    /// Telemetry monitor for this instance of the SDK or `nil` if not configured.
    var telemetry: Telemetry? { get }
}

extension NOOPDatadogCore: DatadogV1CoreProtocol {
    // MARK: - V1 interface

    /// no-op
    func register<T>(feature instance: T?) {}

    /// no-op
    func feature<T>(_ type: T.Type) -> T? {
        return nil
    }

    var context: DatadogV1Context? {
        return nil
    }

    var telemetry: Telemetry? {
        return nil
    }
}
