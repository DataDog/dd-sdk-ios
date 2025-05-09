/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Passthrough core mocks feature-scope allowing recording events in **sync**.
///
/// The `DatadogCoreProtocol` implementation does not require any feature registration,
/// it will always provide a `FeatureScope` with the current context and a `writer` that will
/// store all events in the `events` property.
///
/// Usage:
///
///     let core = PassthroughCoreMock()
///     core.scope(for: "any-feature-name")?.eventWriteContext { context, writer in
///         // will always open a scope
///     }
///
/// The Passthrough core does not allow registering or retrieving a Feature instance.
///
///     let feature = MyCustomFeature()
///     try core.register(feature: feature)
///     core.get(feature: MyCustomFeature.self) // returns nil
///
open class PassthroughCoreMock: DatadogCoreProtocol, FeatureScope, @unchecked Sendable {
    /// Counts references to `PassthroughCoreMock` instances, so we can prevent memory
    /// leaks of SDK core in `DatadogTestsObserver`.
    public private(set) static var referenceCount = 0

    /// Current context that will be passed to feature-scopes.
    @ReadWriteLock
    public var context: DatadogContext {
        didSet { send(message: .context(context)) }
    }

    let writer = FileWriterMock()

    /// The message receiver.
    public var messageReceiver: FeatureMessageReceiver

    /// Callback called when `eventWriteContext` closure is executed.
    public var onEventWriteContext: ((Bool) -> Void)?

    /// Creates a Passthrough core mock.
    ///
    /// - Parameters:
    ///   - context: The testing context.

    public required init(
        context: DatadogContext = .mockAny(),
        dataStore: DataStore = NOPDataStore(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) {
        self.context = context
        self.dataStore = dataStore
        self.messageReceiver = messageReceiver

        messageReceiver.receive(message: .context(context), from: self)

        PassthroughCoreMock.referenceCount += 1
    }

    deinit {
        PassthroughCoreMock.referenceCount -= 1
    }

    /// no-op
    public func register<T>(feature: T) throws where T: DatadogFeature { }
    /// no-op
    public func feature<T>(named name: String, type: T.Type) -> T? { nil }

    /// Always returns a feature-scope.
    public func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        self
    }

    public func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        context.baggages[key] = baggage()
    }

    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        self.context.set(additionalContext: context())
    }

    public func send(message: FeatureMessage, else fallback: () -> Void) {
        if !messageReceiver.receive(message: message, from: self) {
            fallback()
        }
    }

    /// no-op
    public func set(anonymousId: String?) { }

    /// Execute `block` with the current context and a `writer` to record events.
    ///
    /// - Parameter block: The block to execute.
    public func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        block(context, writer)
        onEventWriteContext?(bypassConsent)
    }

    public func context(_ block: @escaping (DatadogContext) -> Void) {
        block(context)
    }

    public var dataStore: DataStore

    /// Recorded events from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    public var events: [Encodable] { writer.events }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.events(ofType: type)
    }

    public func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        return nil
    }
}
