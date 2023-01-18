/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines a read closure for mutating value.
private typealias ContextValueMutation<Value> = (inout Value) -> Void

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

    /// Reads the value synchronously and mutate the value.
    ///
    /// - Parameter receiver: The value to mutate on read.
    func read(to receiver: inout Value)
}

// MARK: - Type-Erasure

/// A reader that performs type erasure by wrapping another reader.
///
/// ``AnyContextValueReader`` is a concrete implementation of ``ContextValueReader``
/// that has no significant properties of its own, and passes through value to its upstream
/// reader.
///
/// Use ``AnyContextValueReader`` to wrap a reader whose type has details
/// you don’t want to expose across API boundaries, such as different modules
///
/// You can use extension method ``ContextValueReader/eraseToAnyReader()``
/// operator to wrap a publisher with ``ContextValueReader``.
internal struct AnyContextValueReader<Value>: ContextValueReader {
    private var mutation: ContextValueMutation<Value>

    /// Creates a type-erasing reader to wrap the provided reader.
    ///
    /// - Parameter reader: A reader to wrap with a type-eraser.
    init<Reader>(_ reader: Reader) where Reader: ContextValueReader, Reader.Value == Value {
        self.mutation = reader.read
    }

    /// Reads the value synchronously and mutate the value.
    ///
    /// - Parameter receiver: The value to mutate on read.
    func read(to receiver: inout Value) {
        mutation(&receiver)
    }
}

extension ContextValueReader {
    /// Wraps this reader with a type eraser.
    ///
    /// Use ``ContextValueReader/eraseToAnyReader()`` to expose an instance of
    /// ``AnyContextValueReader`` to the downstream subscriber, rather than this reader’s
    /// actual type. This form of _type erasure_ preserves abstraction across API boundaries.
    ///
    /// - Returns: An ``AnyContextValueReader`` wrapping this reader.
    func eraseToAnyReader() -> AnyContextValueReader<Value> {
        return AnyContextValueReader(self)
    }
}

// MARK: - Key-path Reader

/// A reader that performs key-path mutations by wrapping other readers.
///
/// ``KeyPathContextValueReader`` keeps an array of mutation operations by calling
/// ``ContextValueReader/read`` to write to a value's property at given ``WritableKeyPath``.
///
/// Use ``KeyPathContextValueReader`` to wrap readers to mutate properties of
/// a value.
internal struct KeyPathContextValueReader<Value> {
    private var mutations: [ContextValueMutation<Value>] = []

    /// Appends a ``ContextValueReader`` instance to set the value's property at a given
    /// `keyPath`.
    ///
    /// - Parameters:
    ///   - reader: The reader to append.
    ///   - keyPath: The value's writable `keyPath`.
    mutating func append<Reader>(reader: Reader, receiver keyPath: WritableKeyPath<Value, Reader.Value>) where Reader: ContextValueReader {
        mutations.append { value in
            reader.read(to: &value[keyPath: keyPath])
        }
    }

    /// Reads the value synchronously and mutate the value.
    ///
    /// - Parameter receiver: The value to mutate on read.
    func read(to receiver: inout Value) {
        mutations.forEach { mutation in
            mutation(&receiver)
        }
    }
}

// MARK: - No-op

/// A no-operation reader.
///
/// ``NOPContextValueReader`` is a concrete implementation of ``ContextValueReader``
/// that has no effect when invoking ``ContextValueReader/read``.
///
/// You can use ``NOPContextValueReader`` as a placeholder.
internal struct NOPContextValueReader<Value>: ContextValueReader {
    func read(to receiver: inout Value) {
        // no-op
    }
}
