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
        didSet { _messageBus.send(message: context) }
    }

    let writer = FileWriterMock()

    /// The legacy `FeatureMessage` receiver.
    public var messageReceiver: FeatureMessageReceiver

    /// The typed message bus. Owns its own dispatcher table and holds a weak reference
    /// to this core so that feature objects storing the bus do not create retain cycles.
    private lazy var _messageBus = PassthroughMessageBusMock(core: self)

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

        PassthroughCoreMock.referenceCount += 1
    }

    deinit {
        PassthroughCoreMock.referenceCount -= 1
    }

    /// The typed message bus — delegates to `_messageBus`.
    public var messageBus: MessageBus { _messageBus }

    /// Subscribes `receiver` to the typed bus and, for `DatadogContext` receivers,
    /// delivers the current context immediately (mirrors `DatadogCore.add(messageReceiver:forKey:)`).
    public func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        _messageBus.subscribe(receiver: receiver)
        if let currentContext = context as? Receiver.Message {
            receiver.receive(message: currentContext, from: self)
        }
    }

    /// Removes `receiver` from the typed bus.
    public func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        _messageBus.unsubscribe(receiver: receiver)
    }

    /// Delivers `message` to the typed bus.
    public func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage {
        _messageBus.send(message: message, else: fallback)
    }

    /// no-op
    public func register<T>(feature: T) throws where T: DatadogFeature { }
    /// no-op
    public func feature<T>(named name: String, type: T.Type) -> T? { nil }

    /// Returns a feature-scope backed by a weak reference to avoid retain cycles.
    public func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        PassthroughScopeMock(core: self)
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

    /// Recorded metadata from feature scopes.
    ///
    /// Invoking the `writer` from the `eventWriteContext` will add
    /// events to this stack.
    public var metadata: [Encodable] { writer.metadata }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.events(ofType: type)
    }

    /// Returns all metadata of the given type.
    ///
    /// - Parameter type: The metadata type to retrieve.
    /// - Returns: A list of metadata of the give type.
    public func metadata<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        writer.metadata(ofType: type)
    }

    public func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        return nil
    }
}

/// A `FeatureScope` backed by a **weak** reference to a `PassthroughCoreMock`.
///
/// Returned by `PassthroughCoreMock.scope(for:)` so that receivers holding the scope
/// do not retain the mock core, preventing retain cycles in tests.
public final class PassthroughScopeMock: FeatureScope, @unchecked Sendable {
    private weak var core: PassthroughCoreMock?

    public init(core: PassthroughCoreMock) {
        self.core = core
    }

    public func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        core?.eventWriteContext(bypassConsent: bypassConsent, block)
    }

    public func context(_ block: @escaping (DatadogContext) -> Void) {
        core?.context(block)
    }

    public var dataStore: DataStore { core?.dataStore ?? NOPDataStore() }

    public var telemetry: Telemetry { core?.telemetry ?? NOPTelemetry() }

    public func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        if let core = core { core.send(message: message, else: fallback) } else { fallback() }
    }

    public func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        core?.set(context: context)
    }

    public func set(anonymousId: String?) {
        core?.set(anonymousId: anonymousId)
    }
}

/// A standalone `MessageBus` returned by `PassthroughCoreMock.messageBus`.
///
/// Owns its own dispatcher table and holds the core **weakly** so that feature objects
/// (e.g. `FatalErrorContextNotifier`) that store the bus do not create retain cycles
/// back to the mock core.
public final class PassthroughMessageBusMock: MessageBus, @unchecked Sendable {
    private typealias Dispatch = (any BusMessage, DatadogCoreProtocol) -> Void

    /// Weak reference stored as `AnyObject` because `DatadogCoreProtocol` is not class-constrained.
    private weak var _core: AnyObject?
    private var core: DatadogCoreProtocol? { _core as? DatadogCoreProtocol }

    /// Per-message-key dispatchers, keyed by receiver identity.
    private var dispatchers: [String: [ObjectIdentifier: Dispatch]] = [:]

    public init(core: DatadogCoreProtocol) {
        self._core = core as AnyObject
    }

    public func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        let id = ObjectIdentifier(receiver)
        dispatchers[Receiver.Message.key, default: [:]][id] = { message, core in
            guard let typed = message as? Receiver.Message else {
                return
            }
            receiver.receive(message: typed, from: core)
        }
    }

    public func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver {
        let id = ObjectIdentifier(receiver)
        dispatchers[Receiver.Message.key]?.removeValue(forKey: id)
    }

    public func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage {
        guard let core = core else {
            fallback()
            return
        }
        guard let bucket = dispatchers[Message.key], !bucket.isEmpty else {
            fallback()
            return
        }
        bucket.values.forEach { $0(message, core) }
    }
}
