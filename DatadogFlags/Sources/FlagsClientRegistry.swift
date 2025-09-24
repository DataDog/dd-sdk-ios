/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A Registry for all FlagsClient instances, allowing access to named instances
/// from anywhere in the application.
public final class FlagsClientRegistry {
    /// Returns the default FlagsClient instance if registered, `NOPFlagsClient` instance otherwise.
    public static var `default`: FlagsClient {
        instances[defaultInstanceName] ?? NOPFlagsClient()
    }

    /// The name for the default FlagsClient instance.
    ///
    /// Features should use this name as default parameter.
    public static let defaultInstanceName = "main"

    @ReadWriteLock
    internal private(set) static var instances: [String: FlagsClient] = [:]

    private init() { }

    /// Register default FlagsClient instance.
    ///
    /// - Parameter instance: The default FlagsClient instance
    public static func register(default instance: FlagsClient) {
        register(instance, named: defaultInstanceName)
    }

    /// Register a FlagsClient instance with the given name.
    ///
    /// If an instance with the same name already exists, this will silently fail
    /// with logging and not crash the application.
    ///
    /// - Parameters:
    ///   - instance: The FlagsClient instance
    ///   - name: The name of the given instance.
    public static func register(_ instance: FlagsClient, named name: String) {
        guard !isRegistered(instanceName: name) else {
            DD.logger.warn("A FlagsClient instance with name '\(name)' has already been registered.")
            return
        }
        instances[name] = instance
    }

    /// Checks if a FlagsClient instance with the specified name is currently registered.
    ///
    /// - Parameter instanceName: The name of the FlagsClient instance to check.
    /// - Returns: `true` if an instance with the given name is registered, otherwise `false`.
    public static func isRegistered(instanceName: String) -> Bool {
        return instances[instanceName] != nil
    }

    /// Unregisters the instance for the given name.
    ///
    /// - Parameter name: The name of the instance to unregister.
    /// - Returns: The instance that was removed, or nil if the key was not present in the registry.
    @discardableResult
    public static func unregisterInstance(named name: String) -> FlagsClient? {
        instances.removeValue(forKey: name)
    }

    /// Unregisters the default instance.
    ///
    /// - Returns: The instance that was removed, or nil if the key was not present in the registry.
    @discardableResult
    public static func unregisterDefault() -> FlagsClient? {
        unregisterInstance(named: defaultInstanceName)
    }

    /// Returns the instance for the given name.
    ///
    /// - Parameter name: The name of the instance to get.
    /// - Returns: The FlagsClient instance if it exists, `NOPFlagsClient` instance otherwise.
    public static func instance(named name: String) -> FlagsClient {
        instances[name] ?? NOPFlagsClient()
    }

    /// Returns all registered instance names.
    ///
    /// - Returns: Array of registered instance names.
    public static func registeredInstanceNames() -> [String] {
        Array(instances.keys)
    }
}
