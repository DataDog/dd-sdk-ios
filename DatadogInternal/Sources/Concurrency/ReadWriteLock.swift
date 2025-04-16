/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A property wrapper using a fair, POSIX conforming reader-writer lock for atomic
/// access to the value.  It is optimised for concurrent reads and exclusive writes.
///
/// The wrapper is a class to prevent copying the lock, it creates and initializes a `pthread_rwlock_t`.
/// An additional method `mutate` allows to safely mutate the value in-place (to read it
/// and write it while obtaining the lock only once).
@propertyWrapper
public final class ReadWriteLock<Value>: @unchecked Sendable {
    /// The wrapped value.
    private var value: Value

    /// The lock object.
    private let rwlock: UnsafeMutablePointer<pthread_rwlock_t>

    public init(wrappedValue value: Value) {
        // allocate on the heap to create a stable pointer
        rwlock = .allocate(capacity: 1)
        rwlock.initialize(to: pthread_rwlock_t())
        pthread_rwlock_init(rwlock, nil)
        self.value = value
    }

    deinit {
        pthread_rwlock_destroy(rwlock)
        rwlock.deinitialize(count: 1)
        rwlock.deallocate()
    }

    /// The wrapped value.
    ///
    /// The `get` will acquire the lock for reading while the `set` will acquire for
    /// writing.
    public var wrappedValue: Value {
        get {
            pthread_rwlock_rdlock(rwlock)
            defer { pthread_rwlock_unlock(rwlock) }
            return value
        }
        set { mutate { $0 = newValue } }
    }

    /// Provides a non-escaping closure for mutation.
    /// The lock will be acquired once for writing before invoking the closure.
    ///
    /// - Parameter closure: The closure with the mutable value.
    @discardableResult
    public func mutate<T>(_ closure: (inout Value) throws -> T) rethrows -> T {
        pthread_rwlock_wrlock(rwlock)
        defer { pthread_rwlock_unlock(rwlock) }
        return try closure(&value)
    }
}
