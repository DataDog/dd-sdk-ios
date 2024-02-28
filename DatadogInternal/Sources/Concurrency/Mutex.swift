/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A property wrapper using a fair, POSIX conforming mutex for atomic
/// access to the value.
///
/// The wrapper is a class to prevent copying the lock, it creates and initilaizes a `pthread_mutex_t`.
/// An additional method `lock` allow to safely mutate the value in-place (to read it
/// and write it while obtaining the lock only once).
@propertyWrapper
public final class Mutex<Value> {
    /// The wrapped value.
    private var value: Value

    /// The mutex object.
    private var mutex = pthread_mutex_t()

    public init(wrappedValue value: Value) {
        pthread_mutex_init(&mutex, nil)
        self.value = value
    }

    deinit {
        pthread_mutex_destroy(&mutex)
    }

    /// The wrapped value.
    ///
    /// The `get` will acquire the lock for reading while the `set` will acquire for
    /// writing.
    public var wrappedValue: Value {
        get {
            pthread_mutex_lock(&mutex)
            defer { pthread_mutex_unlock(&mutex) }
            return value
        }
        set { lock { $0 = newValue } }
    }

    /// Provides a non-escaping closure for mutation.
    /// The lock will be acquired once for writing before invoking the closure.
    ///
    /// - Parameter closure: The closure with the mutable value.
    public func lock<T>(_ closure: (inout Value) throws -> T) rethrows -> T {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        return try closure(&value)
    }
}
