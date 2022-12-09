/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines a receiver closure for receiving new values.
internal typealias ContextValueReceiver<Value> = (Value) -> Void

// MARK: - Publisher

/// Declares that a type can transmit a sequence of values over time.
///
/// The receiver's ``ContextValueReceiver/Value`` generic type must match the
/// ``ContextValuePublisher/Value`` types declared by the publisher.
///
/// A publisher delivers elements to one ``ContextValueReceiver`` closure. After this,
/// the publisher can call the receiver with new values. At anytime, a subcriber can cancel the
/// subscription. Invoking `cancel()` must stop calling its downstream receiver, canceling
/// should also eliminate any strong references it currently holds.
///
/// The publisher provides an `initialValue`, this parameter must be immutable, thead-safe,
/// and it shouldn't block the caller.
///
/// Every ``ContextValuePublisher`` must adhere to this contract for downstream
/// subscribers to function correctly.
internal protocol ContextValuePublisher {
    /// The kind of values published by this publisher.
    associatedtype Value

    /// The initial value of the publisher.
    var initialValue: Value { get }

    /// Start sending values to a receiver.
    func publish(to receiver: @escaping ContextValueReceiver<Value>)

    /// Cancels publications.
    ///
    /// When implementing ``ContextValueSubscription`` in support of a custom publisher,
    /// implement `cancel()` to request that your publisher stop calling its downstream receiver.
    /// It's not required that the publisher stop immediately, but canceling should also eliminate any
    /// strong references it currently holds.
    ///
    /// After you receive one call to `cancel()`, subsequent calls shouldn't do anything. Additionally,
    /// your implementation must be thread-safe, and it shouldn't block the caller.
    func cancel()
}

// MARK: - Subscription

/// A protocol representing the connection of a receiver to a publisher.
///
/// Canceling a ``ContextValueSubscription`` must be thread-safe and you can only cancel a
/// ``ContextValueSubscription`` once.
///
/// Canceling a subscription frees up any resources previously allocated by attaching the
/// ``ContextValueReceiver``.
internal protocol ContextValueSubscription {
    /// Cancels the subcription.
    ///
    /// When implementing ``ContextValueSubscription`` in support of a custom publisher,
    /// implement `cancel()` to request that your publisher stop calling its downstream receiver.
    /// It's not required that the publisher stop immediately, but canceling should also eliminate any
    /// strong references it currently holds.
    ///
    /// After you receive one call to `cancel()`, subsequent calls shouldn't do anything. Additionally,
    /// your implementation must be thread-safe, and it shouldn't block the caller.
    func cancel()
}

/// Attaches a ``ContextValueReceiver`` to a ``ContextValuePublisher`` to create
/// ``ContextValueSubscription`` instance.
///
/// An instance of ``ContextValueBlockSubscription`` is returned when subrcribing to a
/// publisher ``ContextValuePublisher/subscribe``.
///
///     let subscription = publisher.subscribe { value in
///         print(value)
///     }
///
///     subscription.cancel()
///
/// After cancelling the subscription, the publisher is released.
private class ContextValueBlockSubscription<Publisher>: ContextValueSubscription where Publisher: ContextValuePublisher {
    private var publisher: Publisher?

    /// Creates a subscription but subscribing the receiver to the publisher.
    ///
    /// At initialization, the publisher will start publishing to the receiver.
    ///
    /// - Parameters:
    ///   - publisher: The publisher to subscribe.
    ///   - receiver: The receiver closure.
    init(_ publisher: Publisher, receiver: @escaping ContextValueReceiver<Publisher.Value>) {
        self.publisher = publisher
        self.publisher?.publish(to: receiver)
    }

    /// Cancels the publication and free up allocated memory
    func cancel() {
        publisher?.cancel()
        publisher = nil
    }
}

extension ContextValuePublisher {
    /// Subscribes the receiver to the receiver.
    ///
    /// After subscription, the publisher will start invoking the receiver with new values.
    ///
    ///     let subscription = publisher.subscribe { value in
    ///         print(value)
    ///     }
    ///
    /// When no more values are required, the subscription can be cancelled.
    ///
    ///     subscription.cancel()
    ///
    /// - Parameter receiver: The receiver closure.
    /// - Returns: A subscription instance.
    func subscribe(_ receiver: @escaping ContextValueReceiver<Value>) -> ContextValueSubscription {
        return ContextValueBlockSubscription(self, receiver: receiver)
    }
}

// MARK: - Type-Erasure

/// A publisher that performs type erasure by wrapping another publisher.
///
/// ``AnyContextValuePublisher`` is a concrete implementation of ``ContextValuePublisher``
/// that has no significant properties of its own, and passes through values from its upstream
/// publisher.
///
/// Use ``AnyContextValuePublisher`` to wrap a publisher whose type has details
/// you don’t want to expose across API boundaries, such as different modules
///
/// You can use extension method ``ContextValuePublish/ereraseToAnyPublisher()``
/// operator o wrap a publisher with ``AnyContextValuePublisher``.
internal struct AnyContextValuePublisher<Value>: ContextValuePublisher {
    /// The initial value of the publisher.
    let initialValue: Value

    private let publishBlock: (@escaping ContextValueReceiver<Value>) -> Void
    private let cancelBlock: () -> Void

    /// Creates a type-erasing publisher to wrap the provided publisher.
    ///
    /// - Parameter publisher: A publisher to wrap with a type-eraser.
    init<Publisher>(_ publisher: Publisher) where Publisher: ContextValuePublisher, Publisher.Value == Value {
        initialValue = publisher.initialValue
        publishBlock = publisher.publish
        cancelBlock = publisher.cancel
    }

    /// Tells a publisher that it may send more values to the subscriber.
    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        self.publishBlock(receiver)
    }

    /// Cancels publications.
    ///
    /// When implementing ``ContextValueSubscription`` in support of a custom publisher,
    /// implement `cancel()` to request that your publisher stop calling its downstream receiver.
    /// It's not required that the publisher stop immediately, but canceling should also eliminate any
    /// strong references it currently holds.
    ///
    /// After you receive one call to `cancel()`, subsequent calls shouldn't do anything. Additionally,
    /// your implementation must be thread-safe, and it shouldn't block the caller.
    func cancel() {
        self.cancelBlock()
    }
}

extension ContextValuePublisher {
    /// Wraps this publisher with a type eraser.
    ///
    /// Use ``ContextValuePublish/eraseToAnyPublisher()`` to expose an instance of
    /// ``AnyContextValuePublisher`` to the downstream subscriber, rather than this publisher’s
    /// actual type. This form of _type erasure_ preserves abstraction across API boundaries.
    ///
    /// - Returns: An ``AnyContextValuePublisher`` wrapping this publisher.
    func eraseToAnyPublisher() -> AnyContextValuePublisher<Value> {
        return AnyContextValuePublisher(self)
    }
}

// MARK: - No-op

/// A no-operation publisher.
///
/// ``NOPContextValuePublisher`` is a concrete implementation of ``ContextValuePublisher``
/// that has no effect when invoking ``ContextValuePublisher/read``.
///
/// You can use ``NOContextValuePublisher`` as a placeholder.
internal struct NOPContextValuePublisher<Value>: ContextValuePublisher {
    /// The initial value of the reader.
    let initialValue: Value

    /// Creates a type-erasing reader to wrap the provided reader.
    ///
    /// - Parameter reader: A reader to wrap with a type-eraser.
    init(initialValue: Value) {
        self.initialValue = initialValue
    }

    init() where Value: ExpressibleByNilLiteral {
        self.initialValue = nil
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        // no-op
    }

    func cancel() {
        // no-op
    }
}
