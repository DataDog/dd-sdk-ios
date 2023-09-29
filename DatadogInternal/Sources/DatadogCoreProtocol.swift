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
public protocol DatadogCoreProtocol: AnyObject {
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

    /// Retrieves a Feature Scope by its name.
    ///
    /// Feature Scope collects data to Datadog Product (e.g. Logs, RUM, ...). Upon registration, the Feature retrieves
    /// its `FeatureScope` interface for writing events to the core. The core will store and upload events efficiently
    /// according to the performance presets defined on initialization.
    ///
    /// - Parameters:
    ///   - feature: The Feature's name.
    /// - Returns: The Feature scope if a Feature with given name was registered.
    func scope(for feature: String) -> FeatureScope?

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
    ///         let fooID: Int? = try? context.featurebaggages["key"]?.decode()
    ///     }
    ///
    /// - Parameters:
    ///   - baggage: The Feature's baggage to set.
    ///   - key: The baggage's key.
    func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String)

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

extension DatadogCoreProtocol {
    /// Sends a message on the bus shared by features registered in this core.
    ///
    /// - Parameters:
    ///   - message: The message.
    public func send(message: FeatureMessage) {
        send(message: message, else: {})
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
    ///         let fooID: Int? = try? context.featurebaggages["key"]?.decode()
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
    ///         let fooID: Int? = try? context.featurebaggages["key"]?.decode()
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
    ///         let fooID: Int? = try? context.featurebaggages["key"]?.decode()
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
public protocol FeatureScope {
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
    ///   - forceNewBatch: `true` to enforce that event will be written to a separate batch than previous events.
    ///                     Default is `false`, which means the core uses its own heuristic to split events between
    ///                     batches. This parameter can be leveraged in Features which require a clear separation
    ///                     of group of events for preparing their upload (a single upload is always constructed from a single batch).
    ///   - block: The block to execute.
    func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void)
}

/// Feature scope provides a context and a writer to build a record event.
public extension FeatureScope {
    /// Retrieve the event context and writer.
    ///
    /// The Feature scope provides the current Datadog context and event writer
    /// for the Feature to build and record events.
    ///
    /// - Parameters:
    ///   - bypassConsent: `true` to bypass the current core consent and write events as authorized.
    ///                    Default is `false`, setting `true` must still respect user's consent for
    ///                    collecting information.
    ///   - forceNewBatch: `true` to enforce that event will be written to a separate batch than previous events.
    ///                     Default is `false`, which means the core uses its own heuristic to split events between
    ///                     batches. This parameter can be leveraged in Features which require a clear separation
    ///                     of group of events for preparing their upload (a single upload is always constructed from a single batch).
    ///   - block: The block to execute.
    func eventWriteContext(bypassConsent: Bool = false, forceNewBatch: Bool = false, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
        self.eventWriteContext(bypassConsent: bypassConsent, forceNewBatch: forceNewBatch, block)
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
    public func scope(for feature: String) -> FeatureScope? { nil }
    /// no-op
    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) { }
    /// no-op
    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
}
