/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A property wrapper using a fair, POSIX conforming reader-writer lock for atomic
/// access to the value.  It is optimised for concurrent reads and exclusive writes.
///
/// The wrapper is a class to prevent copying the lock, it creates and initilaizes a `pthread_rwlock_t`.
/// An additional method `mutate` allow to safely mutate the value in-place (to read it
/// and write it while obtaining the lock only once).
@propertyWrapper
public final class ReadWriteLock<Value> {
    /// The wrapped value.
    private var value: Value

    /// The lock object.
    private var rwlock = pthread_rwlock_t()

    public init(wrappedValue value: Value) {
        pthread_rwlock_init(&rwlock, nil)
        self.value = value
    }

    deinit {
        pthread_rwlock_destroy(&rwlock)
    }

    /// The wrapped value.
    ///
    /// The `get` will acquire the lock for reading while the `set` will acquire for
    /// writing.
    public var wrappedValue: Value {
        get {
            pthread_rwlock_rdlock(&rwlock)
            defer { pthread_rwlock_unlock(&rwlock) }
            return value
        }
        set {
            pthread_rwlock_wrlock(&rwlock)
            value = newValue
            pthread_rwlock_unlock(&rwlock)
        }
    }

    /// Provides a non-escaping closure for mutation.
    /// The lock will be acquired once for writing before invoking the closure.
    ///
    /// - Parameter closure: The closure with the mutable value.
    public func mutate(_ closure: (inout Value) -> Void) {
        pthread_rwlock_wrlock(&rwlock)
        closure(&value)
        pthread_rwlock_unlock(&rwlock)
    }
}
