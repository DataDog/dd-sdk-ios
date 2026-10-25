/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Executes the provided block synchronously on the queue, or inline when already executing on it.
/// - Parameters:
///   - queue: The serial queue on which to execute the block.
///   - key: A key installed with a non-nil value on `queue`, unique to that queue.
///   - block: A closure that may throw an error.
/// - Returns: The value produced by the closure.
/// - Throws: Whatever the closure itself might throw.
public func runOnQueueSync<T>(_ queue: DispatchQueue, key: DispatchSpecificKey<Void>, _ block: () throws -> T) rethrows -> T {
    if DispatchQueue.getSpecific(key: key) != nil {
        return try block()
    } else {
        return try queue.sync(execute: block)
    }
}

/// Ensures the provided block is executed on the main thread, synchronously, rethrowing any error.
/// - Parameter block: A closure that may throw an error.
/// - Returns: The value produced by the closure.
/// - Throws: Whatever the closure itself might throw.
public func runOnMainThreadSync<T>(_ block: @MainActor () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try MainActor.assumeIsolated {
            return try block()
        }
    } else {
        return try DispatchQueue.main.sync(execute: block)
    }
}
