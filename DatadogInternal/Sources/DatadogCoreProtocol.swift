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
public protocol DatadogCoreProtocol: AnyObject, MessageSending, BaggageSharing {
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
    func get<T>(feature type: T.Type) -> T? where T: DatadogFeature

    /// Retrieves a Feature Scope for given feature type..
    ///
    /// TODO: RUM-3462 update API comment
    ///
    /// - Parameters:
    ///   - type: The Feature instance type.
    /// - Returns: TODO: RUM-3462 update API comment
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature
}

public protocol MessageSending {
    /// Sends a message on the bus shared by features registered in this core.
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

public protocol BaggageSharing {
    /// Sets given baggage for a given Feature for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication chanel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting baggages will update the Core Context that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // Foo.swift
    ///     core.set(baggage: { .init("value") }, forKey: "key")
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let baggage = context.baggages["key"] {
    ///             try {
    ///                 // Try decoding context to expected type:
    ///                 let value: String = try baggage.decode()
    ///                 // If success, handle the `value`.
    ///             } catch {
    ///                 // Otherwise, handle the error (e.g. consider sending as telemetry).
    ///             }
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - baggage: The Feature's baggage to set.
    ///   - key: The baggage's key.
    func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String)
}

extension MessageSending {
    /// Sends a message on the bus shared by features registered in this core.
    ///
    /// - Parameters:
    ///   - message: The message.
    public func send(message: FeatureMessage) {
        send(message: message, else: {})
    }
}

extension BaggageSharing {
    /// Sets given baggage for a given Feature for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication chanel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting baggages will update the Core Context that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // Foo.swift
    ///     core.set(baggage: FeatureBaggage("value"), forKey: "key")
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let baggage = context.baggages["key"] {
    ///             try {
    ///                 // Try decoding context to expected type:
    ///                 let value: String = try baggage.decode()
    ///                 // If success, handle the `value`.
    ///             } catch {
    ///                 // Otherwise, handle the error (e.g. consider sending as telemetry).
    ///             }
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - baggage: The Feature's baggage to set.
    ///   - label: The baggage's label.
    public func set(baggage: FeatureBaggage?, forKey key: String) {
        self.set(baggage: { baggage }, forKey: key)
    }

    /// Sets given baggage for a given Feature for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication chanel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting baggages will update the Core Context that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // Foo.swift
    ///     core.set(baggage: "value", forKey: "key")
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let baggage = context.baggages["key"] {
    ///             try {
    ///                 // Try decoding context to expected type:
    ///                 let value: String = try baggage.decode()
    ///                 // If success, handle the `value`.
    ///             } catch {
    ///                 // Otherwise, handle the error (e.g. consider sending as telemetry).
    ///             }
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - baggage: The Feature's baggage to set.
    ///   - label: The baggage's label.
    public func set<Baggage>(baggage: Baggage?, forKey key: String) where Baggage: Encodable {
        self.set(baggage: { baggage }, forKey: key)
    }

    /// Sets given baggage for a given Feature for sharing data through `DatadogContext`.
    ///
    /// This method provides a passive communication chanel between Features of the Core.
    /// For an active Feature-to-Feature communication, please use the `send(message:)`
    /// method.
    ///
    /// Setting baggages will update the Core Context that is shared across Features.
    /// In the following examples, the Feature `foo` will set an value and a second
    /// Feature `bar` will read it through the event write context.
    ///
    ///     // Foo.swift
    ///     core.set(baggage: { "value" }, forKey: "key")
    ///
    ///     // Bar.swift
    ///     core.scope(for: "bar").eventWriteContext { context, writer in
    ///         if let baggage = context.baggages["key"] {
    ///             try {
    ///                 // Try decoding context to expected type:
    ///                 let value: String = try baggage.decode()
    ///                 // If success, handle the `value`.
    ///             } catch {
    ///                 // Otherwise, handle the error (e.g. consider sending as telemetry).
    ///             }
    ///         }
    ///     }
    ///
    /// - Parameters:
    ///   - baggage: The Feature's baggage to set.
    ///   - label: The baggage's label.
    public func set<Baggage>(baggage: @escaping () -> Baggage?, forKey key: String) where Baggage: Encodable {
        self.set(baggage: { baggage().map(FeatureBaggage.init) }, forKey: key)
    }
}

/// Feature scope provides a context and a writer to build a record event.
public protocol FeatureScope: MessageSending, BaggageSharing {
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

    /// Data store configured for storing data for this feature.
    var dataStore: DataStore { get }

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
    public func get<T>(feature type: T.Type) -> T? where T: DatadogFeature { nil }
    /// no-op
    public func scope<T>(for featureType: T.Type) -> FeatureScope { NOPFeatureScope() }
    /// no-op
    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) { }
    /// no-op
    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
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
    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
    /// no-op
    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) { }
    /// no-op
    public var telemetry: Telemetry { NOPTelemetry() }
}
