/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A typed publish/subscribe channel for messages exchanged between Features
/// registered to the same core.
///
/// Every message is a nominal type conforming to `BusMessage`. Subscribers declare
/// the message type they handle and the bus uses Swift's type system for routing —
/// no runtime casts at the call site, no shared enum to extend when a new message
/// is introduced.
///
/// ## Subscription lifetime
///
/// The bus retains each subscriber until it is explicitly removed via `unsubscribe`.
/// Long-lived subscribers should arrange for unsubscription at teardown. The
/// closure-based convenience (`subscribe(block:)`) returns a `MessageBusSubscription`
/// that callers pass back to `unsubscribe(_:)` to end the subscription.
///
/// ## Threading
///
/// Implementations deliver messages on a serial queue. Receivers may treat state
/// mutations across `receive(message:from:)` calls as serialised, but must not block
/// the caller — doing so delays delivery to every other subscriber.
///
/// ## Choosing receiver- vs closure-based subscription
///
/// - `subscribe(receiver:)` — for long-lived objects that already manage their own
///   lifecycle (Features, instrumentation components).
/// - `subscribe(block:)` — for ad-hoc subscriptions where no natural owner exists;
///   the returned `MessageBusSubscription` is the cleanup anchor.
///
/// - SeeAlso: `BusMessage`, `BusMessageReceiver`, `MessageBusSubscription`.
public protocol MessageBus {
    /// Subscribes `receiver` to messages of type `Receiver.Message`.
    ///
    /// The bus retains `receiver` until `unsubscribe(receiver:)` is called.
    /// Receivers are identified by object identity (`===`); subscribing the same
    /// instance twice is treated as a single subscription.
    func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver

    /// Removes a previously subscribed receiver.
    ///
    /// Identity (`===`) is used to locate the subscription; the call is a no-op if
    /// `receiver` is not currently subscribed.
    func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver

    /// Publishes `message` to every subscriber registered for `Message`.
    ///
    /// If no subscriber is registered for the message kind, `fallback` is invoked
    /// instead. Do not assume which thread the fallback runs on.
    ///
    /// - Parameters:
    ///   - message: The message to publish.
    ///   - fallback: Closure invoked when the message had no subscribers.
    func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage
}

extension MessageBus {
    /// Subscribes a closure to messages of type `Message`.
    ///
    /// A convenience over `subscribe(receiver:)` for the common case where no
    /// natural receiver object exists. The closure is wrapped in an internal
    /// receiver retained by the returned `MessageBusSubscription`; pass that
    /// handle to `unsubscribe(_:)` when the subscription is no longer needed.
    ///
    /// ```swift
    /// let subscription = bus.subscribe { (message: MyMessage, core) in
    ///     // handle message
    /// }
    /// // ... later
    /// bus.unsubscribe(subscription)
    /// ```
    ///
    /// - Parameter block: Called on the bus's delivery queue. Must not block.
    /// - Returns: A handle to pass to `unsubscribe(_:)`.
    func subscribe<Message>(block: @escaping (Message, DatadogCoreProtocol) -> Void) -> MessageBusSubscription where Message: BusMessage {
        let receiver = BusMessageReceiverCallback(block: block)
        self.subscribe(receiver: receiver)
        return MessageBusSubscription(receiver)
    }

    /// Removes the subscription created by `subscribe(block:)`.
    ///
    /// Idempotent — additional calls with the same `subscription` are no-ops.
    func unsubscribe(_ subscription: MessageBusSubscription) {
        subscription.unsubscribe(from: self)
    }

    /// Publishes `message` to every subscriber registered for `Message`.
    ///
    /// Convenience over `send(message:else:)` for the common case where the
    /// caller doesn't care whether the message was consumed.
    public func send<Message>(message: Message) where Message: BusMessage {
        send(message: message, else: {})
    }
}

/// An opaque, type-erased handle to a closure-based subscription on a `MessageBus`.
///
/// Returned by `MessageBus.subscribe(block:)`. The handle owns the internal receiver
/// wrapping the caller's closure: store it for the lifetime of the subscription, then
/// pass it to `MessageBus.unsubscribe(_:)` to end delivery.
///
/// Instances cannot be constructed directly.
public final class MessageBusSubscription {
    private let receiver: AnyObject
    private let _unsubscribe: (MessageBus) -> Void

    fileprivate init<Message>(_ receiver: BusMessageReceiverCallback<Message>) where Message: BusMessage {
        self.receiver = receiver
        self._unsubscribe = { bus in bus.unsubscribe(receiver: receiver) }
    }

    fileprivate func unsubscribe(from bus: MessageBus) {
        _unsubscribe(bus)
    }
}

/// A typed payload carried on a `MessageBus`.
///
/// Each conforming type represents a distinct kind of message. The bus routes by
/// type — conformance is the only registration step required.
///
/// ## Conformance guidance
///
/// - Prefer immutable value types (`struct`, or `enum` for closed variants). A
///   `BusMessage` should survive queue hops without aliasing surprises.
/// - `key` is a stable identifier used for diagnostics and telemetry. It must be
///   globally unique across the SDK; namespaced identifiers
///   (e.g. `"rum.session.start"`) are recommended.
public protocol BusMessage {
    /// A stable, globally unique identifier for this message kind.
    ///
    /// Used by logs, telemetry, and any out-of-band consumer that refers to messages
    /// by name. Treat the string as part of the public contract — changing it is a
    /// breaking change for downstream tooling.
    static var key: String { get }
}

/// A consumer of a single `BusMessage` type.
///
/// The protocol is class-bound (`AnyObject`) because the bus tracks subscriptions
/// by object identity. The concrete `Message` is fixed per receiver — to handle
/// multiple message kinds, register multiple receivers.
public protocol BusMessageReceiver: AnyObject {
    /// The message kind this receiver consumes.
    associatedtype Message: BusMessage

    /// Handles a delivered message.
    ///
    /// Called on the bus's delivery queue. Implementations must not block the
    /// caller — doing so delays delivery to every other subscriber.
    ///
    /// - Parameters:
    ///   - message: The delivered value, statically typed as `Message`.
    ///   - core: The core from which the message was emitted. Capture transiently;
    ///     do not retain.
    func receive(message: Message, from core: DatadogCoreProtocol)
}

/// A no-op `MessageBus`.
///
/// Subscribe and unsubscribe calls have no effect; no message is ever delivered.
/// Used as a safe default for cores that have not yet wired up a real bus and as a
/// stand-in in tests where bus behaviour is irrelevant.
public struct NOPMessageBus: MessageBus {
    public init() { }

    /// no-op
    public func subscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver { }

    /// no-op
    public func unsubscribe<Receiver>(receiver: Receiver) where Receiver: BusMessageReceiver { }

    /// no-op
    public func send<Message>(message: Message, else fallback: @escaping () -> Void) where Message: BusMessage { }
}

/// Adapts a free closure to `BusMessageReceiver`. Internal-only — exposed exclusively
/// through `MessageBus.subscribe(block:)`.
private final class BusMessageReceiverCallback<Message>: BusMessageReceiver where Message: BusMessage {
    typealias Block = (Message, DatadogCoreProtocol) -> Void

    let block: Block

    init(block: @escaping Block) {
        self.block = block
    }

    func receive(message: Message, from core: DatadogCoreProtocol) {
        block(message, core)
    }
}
