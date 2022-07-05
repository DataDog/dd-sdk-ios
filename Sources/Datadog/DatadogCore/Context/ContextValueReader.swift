/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Declares that a type can read values on demand.
///
/// A reader delivers elements to the receiver callback synchronously.
/// The receiver's ``ContextValueReceiver/Value`` generic type must match the
/// ``ContextValueReader/Value`` types declared by the reader.
///
/// The reader implements the ``ContextValuePublisher/read(_:)`` method
/// to read the value and call the receiver.
internal protocol ContextValueReader {
    /// The kind of values this reader reads.
    associatedtype Value

    /// The initial value of the reader.
    var initialValue: Value { get }

    /// Reads the value synchronously and calls the **nonescaping** receiver.
    ///
    /// - Parameter receiver: The closure to execute after reading a value.
    func read(_ receiver: ContextValueReceiver<Value>)
}

// MARK: - Type-Erasure

/// A reader that performs type erasure by wrapping another reader.
///
/// ``AnyContextValueReader`` is a concrete implementation of ``ContextValueReader``
/// that has no significant properties of its own, and passes through values from its upstream
/// reader.
///
/// Use ``AnyContextValueReader`` to wrap a reader whose type has details
/// you don’t want to expose across API boundaries, such as different modules
///
/// You can use extension method ``ContextValueReader/eraseToAnyReader()``
/// operator to wrap a publisher with ``ContextValueReader``.
internal struct AnyContextValueReader<Value>: ContextValueReader {
    /// The initial value of the reader.
    let initialValue: Value

    private let send: (ContextValueReceiver<Value>) -> Void

    /// Creates a type-erasing reader to wrap the provided reader.
    ///
    /// - Parameter reader: A reader to wrap with a type-eraser.
    init<Reader>(_ reader: Reader) where Reader: ContextValueReader, Reader.Value == Value {
        self.initialValue = reader.initialValue
        self.send = reader.read
    }

    /// Reads the value synchronously and calls the **nonescaping** receiver.
    ///
    /// - Parameter receiver: The closure to execute after reading a value.
    func read(_ receive: ContextValueReceiver<Value>) {
        self.send(receive)
    }
}

extension ContextValueReader {
    /// Wraps this reader with a type eraser.
    ///
    /// Use ``ContextValueReader/eraseToAnyReader()`` to expose an instance of
    /// ``AnyContextValueReader`` to the downstream subscriber, rather than this reader’s
    /// actual type. This form of _type erasure_ preserves abstraction across API boundaries.
    ///
    /// - Returns: An ``AnyContextValuePublisher`` wrapping this reader.
    func eraseToAnyReader() -> AnyContextValueReader<Value> {
        return AnyContextValueReader(self)
    }
}
