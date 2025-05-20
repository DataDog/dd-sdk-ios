/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A Datadog Core holds a set of Features and is responsible for managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
///
/// Any reference to `DatadogCoreProtocol` must be captured as `weak` within a Feature. This is to avoid
/// retain cycle of core holding the Feature and vice-versa.
public protocol DatadogCoreProtocol: AnyObject, MessageSending, AdditionalContextSharing, Storage {
    // Remove `DatadogCoreProtocol` conformance to `MessageSending` and `BaggageSharing` once
    // all features are migrated to depend on `FeatureScope` interface.

    /// Registers a Feature instance.
    ///
    /// Feature can interact with the core and other Feature through the message bus. Some specific Features
    /// complying to `DatadogRemoteFeature` can collect and transfer data to a Datadog Product
    /// (e.g. Logs, RUM, ...). Upon registration, a Remote Feature can retrieve a `FeatureScope` interface
    /// for writing events to the core. The core will store and upload events efficiently according to the performance
    /// presets defined on initialization.
    ///
    /// - Parameter feature: The Feature instance - it will be retained and held by core.
    func register<T>(feature: T) throws where T: DatadogFeature

    /// Retrieves previously registered Feature by its name and type.
    ///
    /// A Feature type can be specified as parameter or inferred from the return type:
    ///
    ///     let feature = core.feature(named: "foo", type: Foo.self)
    ///     let feature: Foo? = core.feature(named: "foo")
    ///
    /// - Parameters:
    ///   - name: The Feature's name.
    ///   - type: The Feature instance type.
    /// - Returns: The Feature if any.
    func feature<T>(named name: String, type: T.Type) -> T?

    /// Retrieves a Feature Scope for given feature type.
    ///
    /// The scope manages the underlying core's reference in safe way, guaranteeing no reference leaks.
    /// It is available right away even before the feature registration completes in the core, so some capabilities
    /// might be not available before the feature is fully registered.
    ///
    /// If possible, feature implementation must to take dependency on `FeatureScope` rather than `DatadogCoreProtocol` itself.
    ///
    /// - Parameters:
    ///   - type: The Feature instance type.
    /// - Returns: The scope for requested feature type.
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature
}

extension DatadogCoreProtocol {
    /// Returns a `DatadogFeature` conforming type from the
    /// Feature registry.
    ///
    /// - Parameter type: The Feature instance type.
    /// - Returns: The Feature if any.
    public func get<T>(feature type: T.Type = T.self) -> T? where T: DatadogFeature {
        feature(named: T.name, type: type)
    }
}

public protocol MessageSending {
    /// Sends a message on the bus shared by features registered to the sam core.
    ///
    /// If the message could not be processed by any registered feature, the fallback closure
    /// will be invoked. Do not make any assumption on which thread the fallback is called.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - fallback: The fallback closure to call when the message could not be
    ///               processed by any Features on the bus.
    func send(message: FeatureMessage, else fallback: @escaping () -> Void)
}

extension MessageSending {
    /// Sends a message on the bus shared by features registered to the same core.
    ///
    /// - Parameters:
    ///   - message: The message.
    public func send(message: FeatureMessage) {
        send(message: message, else: {})
    }
}

public protocol AdditionalContextSharing {
    /// Sets additional context for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication channel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting context will update the Core Context's additional property that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // MyContext.swift
    ///     struct MyContext: AdditionalContext {
    ///         static let key = "my-context"
    ///         let value: String
    ///     }
    ///
    ///     // Foo.swift
    ///     core.set(context: { MyContext(value: "value") })
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let value = context.additionalContext(ofType: MyContext.self) {
    ///             // If success, handle the `value`.
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - context: The additional context to set.
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext
}

extension AdditionalContextSharing {
    /// Sets additional context for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication channel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting context will update the Core Context's additional property that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // MyContext.swift
    ///     struct MyContext: AdditionalContext {
    ///         static let key = "my-context"
    ///         let value: String
    ///     }
    ///
    ///     // Foo.swift
    ///     core.set(context: MyContext(value: "value"))
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let value = context.additionalContext(ofType: MyContext.self) {
    ///             // If success, handle the `value`.
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - context: The additional context to set.
    public func set<Context>(context: Context?) where Context: AdditionalContext {
        set(context: { context })
    }

    /// Removes additional context from `DatadogContext`.
    ///
    /// This method provides a passive communication channel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Removing context will update the Core Context's additional property that is shared across Features.
    /// 
    /// - Parameters:
    ///   - type: The context's type to remove.
    public func removeContext<Context>(ofType type: Context.Type) where Context: AdditionalContext {
        set(context: { nil as Context? })
    }
}

/// Provides ability to set or clear the anonymous identifier needed for session linking.
public protocol AnonymousIdentifierManaging {
    /// Sets the anonymous identifier.
    /// - Parameter anonymousId: The anonymous id to be set. When `nil` it will clear the current anonymous id.
    func set(anonymousId: String?)
}

/// Feature scope provides a context and a writer to build a record event.
public protocol FeatureScope: MessageSending, AdditionalContextSharing, AnonymousIdentifierManaging, Sendable {
    /// Retrieve the core context and event writer.
    ///
    /// The Feature scope provides the current Datadog context and event writer for building and recording events.
    /// The provided context is valid at the moment of the call, meaning that it includes all changes that happened
    /// earlier on the same thread.
    ///
    /// A Feature has the ability to bypass the current user consent for data collection. Set `bypassConsent` to `true`
    /// only if the Feature is already aware of the user's consent for the event it is about to write.
    ///
    /// - Parameters:
    ///   - bypassConsent: `true` to bypass the current core consent and write events as authorized.
    ///                    Default is `false`, setting `true` must still respect user's consent for
    ///                    collecting information.
    ///   - block: The block to execute; it is called on the context queue.
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void)

    /// Retrieve the core context.
    ///
    /// A feature can use this method to request the Datadog context valid at the moment of the call.
    ///
    /// - Parameter block: The block to execute; it is called on the context queue.
    func context(_ block: @escaping (DatadogContext) -> Void)

    /// Data store endpoint.
    ///
    /// Use this property to store data for this feature. Data will be persisted between app launches.
    var dataStore: DataStore { get }

    /// Telemetry endpoint.
    ///
    /// Use this property to report any telemetry event to the core.
    var telemetry: Telemetry { get }
}

/// Feature scope provides a context and a writer to build a record event.
public extension FeatureScope {
    /// Retrieve the core context and event writer.
    ///
    /// The Feature scope provides the current Datadog context and event writer for building and recording events.
    /// The provided context is valid at the moment of the call, meaning that it includes all changes that happened
    /// earlier on the same thread.
    ///
    /// A Feature has the ability to bypass the current user consent for data collection. Set `bypassConsent` to `true`
    /// only if the Feature is already aware of the user's consent for the event it is about to write.
    ///
    /// - Parameters:
    ///   - bypassConsent: `true` to bypass the current core consent and write events as authorized.
    ///                    Default is `false`, setting `true` must still respect user's consent for
    ///                    collecting information.
    ///   - forceNewBatch: `true` to enforce that event will be written to a separate batch than previous events.
    ///                     Default is `false`, which means the core uses its own heuristic to split events between
    ///                     batches. This parameter can be leveraged in Features which require a clear separation
    ///                     of group of events for preparing their upload (a single upload is always constructed from a single batch).
    ///   - block: The block to execute; it is called on the context queue.
    func eventWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void) {
        eventWriteContext(bypassConsent: false, block)
    }

    /// Retrieve the core context and data store.
    ///
    /// Can be used to store data that depends on the current Datadog context. The provided context is valid at the moment
    /// of the call, meaning that it includes all changes that happened earlier on the same thread.
    ///
    /// - Parameter block: The block to execute; it is called on the context queue.
    func dataStoreContext(_ block: @escaping (DatadogContext, DataStore) -> Void) {
        context { context in
            block(context, dataStore)
        }
    }
}

/// No-op implementation of `DatadogFeatureRegistry`.
public class NOPDatadogCore: DatadogCoreProtocol {
    public init() { }
    /// no-op
    public func register<T>(feature: T) throws where T: DatadogFeature { }
    /// no-op
    public func feature<T>(named name: String, type: T.Type) -> T? { nil }
    /// no-op
    public func scope<T>(for featureType: T.Type) -> FeatureScope { NOPFeatureScope() }
    /// no-op
    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { }
    /// no-op
    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
    /// no-op
    public func mostRecentModifiedFileAt(before: Date) throws -> Date? { return nil }
}

public struct NOPFeatureScope: FeatureScope {
    public init() { }
    /// no-op
    public func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) { }
    /// no-op
    public func context(_ block: @escaping (DatadogContext) -> Void) { }
    /// no-op
    public var dataStore: DataStore { NOPDataStore() }
    /// no-op
    public var telemetry: Telemetry { NOPTelemetry() }
    /// no-op
    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
    /// no-op
    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { }
    /// no-op
    public func set(anonymousId: String?) { }
}
