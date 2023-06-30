/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A Registry for all core instances, allowing Features to retrieve the one
/// they want from anywhere.
public final class CoreRegistry {
    /// Returns the default core instance if registered, `NOPDatadogCore` instance otherwise.
    public static var `default`: DatadogCoreProtocol {
        instances[defaultInstanceName] ?? NOPDatadogCore()
    }

    /// The name for the default core instance.
    ///
    /// Features should use this name as default parameter.
    public static let defaultInstanceName = "main"

    @ReadWriteLock
    private static var instances: [String: DatadogCoreProtocol] = [:]

    private init() { }

    /// Register default core instance.
    ///
    /// - Parameter instance: The default core instance
    public static func register(default instance: DatadogCoreProtocol) {
        register(instance, named: defaultInstanceName)
    }

    /// Register an instance of core instance with the given name.
    ///
    /// - Parameters:
    ///   - instance: The core instance
    ///   - name: The name of the given instance.
    public static func register(_ instance: DatadogCoreProtocol, named name: String) {
        if instances[name] == nil {
            instances[name] = instance
        } else {
            DD.logger.warn("A core instance with name \(name) has already been registered.")
        }
    }

    /// Unregisters the instance for the given name.
    ///
    /// - Parameter name: The name of the instance to unregister.
    /// - Returns: The instance that was removed, or nil if the key was not present in the registry.
    @discardableResult
    public static func unregisterInstance(named name: String) -> DatadogCoreProtocol? {
        instances.removeValue(forKey: name)
    }

    /// Unregisters the default instance.
    ///
    /// - Returns: The instance that was removed, or nil if the key was not present in the registry.
    @discardableResult
    public static func unregisterDefault() -> DatadogCoreProtocol? {
        unregisterInstance(named: defaultInstanceName)
    }

    /// Returns the instance for the given name.
    ///
    /// - Parameter name: The name of the instance to get.
    /// - Returns: The core instance if it exists, `NOPDatadogCore` instance otherwise.
    public static func instance(named name: String) -> DatadogCoreProtocol {
        instances[name] ?? NOPDatadogCore()
    }
}
