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
        self as? DatadogV1CoreProtocol ?? NOPDatadogCore()
    }
}

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
internal protocol DatadogV1CoreProtocol: DatadogCoreProtocol {
    // MARK: - V1 interface

    /// The SDK context created upon core initialization or `nil` if SDK was not yet initialized.
    var context: DatadogV1Context? { get }

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
    func scope<T>(for featureType: T.Type) -> FeatureV1Scope?
}

/// Feature scope in v1 provide a context and a writer to build a record event.
internal protocol FeatureV1Scope {
    /// Retrieve the event context and writer.
    ///
    /// The Feature scope provides the current Datadog context and event writer
    /// for the Feature to build and record events.
    ///
    /// A Feature has the ability to bypass the current user consent for data collection. The `bypassConsent`
    /// must be set to `true` only if the Feature is already aware of the user's consent for the event it is about
    /// to write.
    ///
    /// - Parameters:
    ///   - bypassConsent: `true` to bypass the current core consent and write events as authorized.
    ///                    Default is `false`, setting `true` must still respect user's consent for
    ///                    collecting information.
    ///   - block: The block to execute.
    func eventWriteContext(bypassConsent: Bool, _ block: (DatadogV1Context, Writer) throws -> Void)
}

/// Feature scope in v1 provide a context and a writer to build a record event.
extension FeatureV1Scope {
    /// Retrieve the event context and writer.
    ///
    /// The Feature scope provides the current Datadog context and event writer
    /// for the Feature to build and record events.
    ///
    /// - Parameter block: The block to execute.
    func eventWriteContext(_ block: (DatadogV1Context, Writer) throws -> Void) {
        self.eventWriteContext(bypassConsent: false, block)
    }
}

extension NOPDatadogCore: DatadogV1CoreProtocol {
    // MARK: - V1 interface

    /// Returns `nil`.
    var context: DatadogV1Context? {
        return nil
    }

    /// no-op
    func register<T>(feature instance: T?) {}

    /// no-op
    func feature<T>(_ type: T.Type) -> T? {
        return nil
    }

    /// no-op
    func scope<T>(for featureType: T.Type) -> FeatureV1Scope? {
        return nil
    }
}
